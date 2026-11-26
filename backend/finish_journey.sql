-- Review and test in staging before applying. No trigger bypass or service-role key.
begin;
create or replace function public.finish_mobile_journey(p_owner_id uuid,p_journey_id text,p_expected_version timestamptz)
returns jsonb
language plpgsql security invoker set search_path = ''
as $fn$
declare
  j public.journey_sync_records%rowtype;
  a public.animal_sync_records%rowtype;
  item jsonb;
  ev jsonb;
  old_event jsonb;
  actor jsonb;
  context jsonb;
  stamp text := to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  pending integer;
  attended integer := 0;
  result jsonb;
  event_id text;
begin
  if auth.uid() is null or not public.is_ranch_admin(p_owner_id) then
    raise exception 'Solo un administrador puede finalizar jornadas desde esta versión.' using errcode='42501';
  end if;
  context := public.get_my_ranch_context();
  if context->>'owner_id' is distinct from p_owner_id::text or context->>'status' is distinct from 'active' then
    raise exception 'Membresía inválida' using errcode='42501';
  end if;
  actor := jsonb_build_object('authUserId',auth.uid(),'email',coalesce(auth.jwt()->>'email',''),'label',context->>'display_name');
  select * into j from public.journey_sync_records where owner_id=p_owner_id and journey_id=p_journey_id for update;
  if not found then raise exception 'Jornada no encontrada'; end if;
  if j.payload->>'status' in ('completed','incomplete') then return j.payload; end if;
  if j.updated_at is distinct from p_expected_version or j.payload->>'status' is distinct from 'in_progress' then
    raise exception 'La jornada cambió; actualiza antes de finalizar' using errcode='40001';
  end if;
  if j.payload->>'id' is distinct from p_journey_id or coalesce(j.payload->>'type','') not in ('weight','bath','vaccine','deworm','injection','medication','review') or jsonb_typeof(j.payload->'roster') is distinct from 'array' then raise exception 'Jornada inválida'; end if;
  if (select count(*) from jsonb_array_elements(j.payload->'roster')) <> (select count(distinct value->>'id') from jsonb_array_elements(j.payload->'roster')) then raise exception 'Animales duplicados'; end if;
  perform (j.payload->>'date')::date;
  select count(*) into pending from jsonb_array_elements(j.payload->'roster') where value->'attended' is distinct from 'true'::jsonb;
  for item in select value from jsonb_array_elements(j.payload->'roster') where value->'attended'='true'::jsonb order by value->>'id'
  loop
    select * into a from public.animal_sync_records where owner_id=p_owner_id and animal_id=item->>'id' and deleted_at is null for update;
    if not found or jsonb_typeof(a.payload->'events') is distinct from 'array' then raise exception 'Ficha no disponible: %',item->>'id'; end if;
    if jsonb_typeof(item->'attendedBy') is distinct from 'object' or coalesce(item->>'attendedAt','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' then raise exception 'Atención sin auditoría'; end if;
    if j.payload->>'type'='weight' and (coalesce(item->>'weight','') !~ '^[0-9]+([.][0-9]+)?$' or (item->>'weight')::numeric>100000) then raise exception 'Peso inválido'; end if;
    event_id := 'journey:'||p_journey_id||':'||a.animal_id;
    ev := jsonb_build_object('id',event_id,'animalId',a.animal_id,'journeyId',p_journey_id,'type',j.payload->>'type','date',j.payload->>'date','label',coalesce(j.payload->>'product',''),'product','','dose',coalesce(j.payload->>'dose',''),'notes',coalesce(j.payload->>'notes',''),'createdAt',item->>'attendedAt','performedAt',item->>'attendedAt','performedBy',item->'attendedBy');
    if j.payload->>'type'='weight' then
      ev:=ev||jsonb_build_object('weight',item->'weight');
      if item ? 'weightUpdatedAt' then ev:=ev||jsonb_build_object('weightUpdatedAt',item->'weightUpdatedAt'); end if;
      if item ? 'weightUpdatedBy' then ev:=ev||jsonb_build_object('weightUpdatedBy',item->'weightUpdatedBy'); end if;
    end if;
    select value into old_event from jsonb_array_elements(a.payload->'events') where value->>'id'=event_id;
    if found then
      if old_event is distinct from ev then raise exception 'Conflicto con evento existente: %',event_id; end if;
    else
      update public.animal_sync_records set payload=jsonb_set(payload,'{events}',(payload->'events')||jsonb_build_array(ev)) where owner_id=p_owner_id and animal_id=a.animal_id;
      if not found then raise exception 'No se pudo guardar historial'; end if;
    end if;
    attended:=attended+1;
  end loop;
  result:=j.payload||jsonb_build_object('status',case when pending=0 then 'completed' else 'incomplete' end,'completedAt',stamp,'completedBy',actor,'updatedAt',stamp);
  update public.journey_sync_records set payload=result where owner_id=p_owner_id and journey_id=p_journey_id;
  if not found then raise exception 'No se pudo cerrar jornada'; end if;
  return result;
end;
$fn$;
revoke all on function public.finish_mobile_journey(uuid,text,timestamptz) from public,anon;
grant execute on function public.finish_mobile_journey(uuid,text,timestamptz) to authenticated;
commit;
