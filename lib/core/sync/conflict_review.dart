String conflictExplanation(String code) => switch(code){
  'OPERATION_ID_REUSED'=>'El identificador ya fue usado con otros datos o por otro usuario. No lo reenvíes con cambios.',
  'ENTITY_ID_REUSED'=>'Ya existe un evento con este identificador. Consulta el historial antes de registrar otra actividad.',
  'MEMBERSHIP_REQUIRED'=>'No tienes acceso activo al rancho. Solicita revisión de tus permisos.',
  'ANIMAL_NOT_AVAILABLE'=>'El animal ya no está disponible. Revisa su ficha antes de registrar otra actividad.',
  'ANIMAL_INACTIVE'=>'El animal está archivado o inactivo. Solicita revisión al administrador.',
  'INVALID_REQUEST'=>'Los datos de la operación no cumplen el contrato. Revisa la captura original.',
  _=>'La operación requiere revisión. No se enviará automáticamente otra vez.',
};