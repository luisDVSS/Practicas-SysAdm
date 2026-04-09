## INSTRUCCIONES 
Enfoque: Endurecimiento (Hardening) del Directorio Activo (Active Directory - AD), Auditoría de Eventos y Autenticación de Múltiples Factores (Multi-Factor Authentication - MFA).
Objetivo de la Actividad
Elevar el nivel de seguridad del dominio mediante la implementación de un modelo de Control de Acceso Basado en Roles (Role-Based Access Control - RBAC) y una capa de Autenticación de Múltiples Factores (Multi-Factor Authentication - MFA). El estudiante deberá demostrar su capacidad para orquestar la seguridad administrativa, auditar cambios críticos en el sistema y proteger el acceso al servidor mediante factores de autenticación dinámicos.
Actividades 

1. Delegación de Control y RBAC (Roles Específicos)
Configuración: Crear 4 usuarios de administración delegada para tareas específicas dentro del Directorio Activo (Active Directory - AD).
Configurar permisos granulares mediante Listas de Control de Acceso (Access Control Lists - ACL) en los contenedores de AD.
Especificación de Roles Delegados (RBAC)
Rol 1: Operador de Identidad y Acceso (IAM Operator)
Usuario: admin_identidad

Responsabilidad Primaria: Gestión del ciclo de vida de los usuarios de las Unidades Organizativas (Organizational Units - OU) "Cuates" y "No Cuates".

Tareas Específicas: 
Crear, eliminar y modificar cuentas de usuario.
Gestionar el restablecimiento de contraseñas (Password Reset) y desbloqueo de cuentas.
Modificar atributos básicos (Teléfono, Oficina, Correo).
Restricción Crítica: No puede modificar la pertenencia a grupos de seguridad de nivel "Domain Admin" ni alterar las Directivas de Grupo (Group Policy Objects - GPO).
Rol 2: Operador de Almacenamiento y Recursos (Storage Operator)
Usuario: admin_storage

Responsabilidad Primaria: Gestión de cuotas de disco y cumplimiento de políticas de archivos mediante el Administrador de Recursos del Servidor de Archivos (File Server Resource Manager - FSRM).

Tareas Específicas:
Crear y modificar límites de Cuotas de Disco (Quotas).Configurar y actualizar el Apantallamiento de Archivos (File Screening) para bloquear extensiones prohibidas.Generar reportes de uso de almacenamiento en el servidor.

Restricción Crítica: Mediante la edición de las Listas de Control de Acceso (Access Control Lists - ACL), se le debe denegar explícitamente el permiso Reset Password sobre cualquier objeto de usuario en el Directorio Activo (Active Directory - AD).
Rol 3: Administrador de Cumplimiento y Directivas (GPO Compliance)Usuario: admin_politicas
Responsabilidad Primaria: Implementación y mantenimiento de las configuraciones de seguridad del entorno de trabajo.

Tareas Específicas:
Vincular (Link) y desvincular Objetos de Directiva de Grupo (Group Policy Objects - GPO) existentes a las Unidades Organizativas (OU).Modificar la configuración de AppLocker y las Restricciones de Horario (Logon Hours).Gestionar las Directivas de Contraseña Ajustada (Fine-Grained Password Policy - FGPP).

Restricción Crítica: Tiene permiso de "Lectura" en todo el dominio, pero solo tiene permiso de "Escritura" sobre los objetos de tipo GPO, no sobre las cuentas de usuario.
Rol 4: Auditor de Seguridad y Eventos (Security Auditor)
Usuario: admin_auditoria

Responsabilidad Primaria: Monitoreo de la integridad del sistema y detección de intentos de intrusión.

Tareas Específicas:
Acceso de lectura a los Registros de Seguridad (Security Logs) del Visor de Eventos (Event Viewer).Ejecución del script de extracción de "Accesos Denegados" e intentos fallidos de Autenticación de Múltiples Factores (Multi-Factor Authentication - MFA).Verificación del estado de la Auditoría de Acceso a Objetos.

Restricción Crítica: Este usuario es estrictamente de lectura (Read-Only). No debe tener permisos para modificar ningún objeto, usuario o política en el dominio.2. Directivas de Contraseña y Auditoría de Eventos
Directiva de Contraseña Ajustada (Fine-Grained Password Policy - FGPP): Implementar mediante PowerShell una política que exija una longitud mínima de 12 caracteres para cuentas con privilegios administrativos y de 8 caracteres para usuarios estándar.
Hardening de Auditoría: Habilitar la auditoría de éxito y fallo en el acceso a objetos y el inicio de sesión.
Script de Monitoreo: El estudiante debe generar un script que extraiga automáticamente del Visor de Eventos (Event Viewer) los últimos 10 eventos de "Acceso Denegado" (ID 4625 o similar) y los exporte a un archivo de texto plano para revisión administrativa.
3. Implementación de MFA (Google Authenticator)
Integración Técnica: Instalar y configurar un software de autenticación (como WinOTP, un agente RADIUS o un Proveedor de Credenciales de terceros) que integre el algoritmo de Contraseña Temporal de un Solo Uso (Time-based One-Time Password - TOTP).
Validación: El inicio de sesión en el Windows Server debe exigir obligatoriamente el código dinámico generado por la aplicación Google Authenticator.
Configurar el sistema para que, tras 3 intentos fallidos de Autenticación de Múltiples Factores (Multi-Factor Authentication - MFA), la cuenta de usuario se bloquee automáticamente por un periodo de 30 minutos.
Herramientas y Comandos Críticos
Delegación en AD: Uso de la herramienta de línea de comandos para Listas de Control de Acceso a Servicios de Directorio (dsacls) o el comando de PowerShell Set-Acl aplicado sobre la unidad de AD.
Auditoría de Políticas: Ejecución de auditpol /set /subcategory:"Logon" /success:enable /failure:enable para rastrear intentos de acceso.
Gestión de FGPP: Uso del cmdlet New-ADFineGrainedPasswordPolicy para segmentar la seguridad de las contraseñas.
Interfaz de MFA: Instalación de un Proveedor de Credenciales (Credential Provider) que actúe como filtro entre la Pantalla de Inicio de Sesión de Windows y el Servicio de Subsistema de Autoridad de Seguridad Local (Local Security Authority Subsystem Service - LSASS).
Rúbrica de Evaluación (Práctica 09)
La calificación de esta práctica se basa en la integridad de la cadena de seguridad implementada:Implementación de MFA (40%): Se validará que el acceso al servidor sea imposible sin el código de Google Authenticator. Se penalizará si existen "puertas traseras" que permitan saltar este factor.Delegación de Roles y RBAC (30%): Se comprobará físicamente que los usuarios delegados tengan restringidas las funciones que no pertenecen a su perfil (ej. intentar resetear una contraseña con el Rol 2 debe fallar).Auditoría y Directivas (15%): Evaluación del reporte generado por script y verificación de que la complejidad de la contraseña se ajusta según el tipo de usuario (FGPP).Documentación Técnica (15%): El documento formal debe explicar con diagramas el flujo de autenticación (desde el ingreso de la contraseña hasta la validación del token TOTP) y describir el proceso de configuración del bloqueo automático de cuenta.Protocolo de Pruebas:
Servicios: Delegación (RBAC), Directivas de Contraseña (FGPP) y MFA.Test 1: Verificación de Delegación (Rol 2 vs Rol 1)
Acción A: Iniciar sesión como admin_identidad y cambiar la contraseña de un usuario de la Unidad Organizativa (OU) "Cuates".
Acción B: Iniciar sesión como admin_storage e intentar la misma acción de cambio de contraseña.
Resultado esperado: La Acción A debe ser exitosa; la Acción B debe mostrar "Acceso Denegado" (validación de la ACL de denegación).
Evidencia para el reporte: Capturas comparativas de ambos intentos (uno exitoso y uno fallido).
Test 2: Directiva de Contraseña Ajustada (Fine-Grained Password Policy - FGPP)
Acción: Intentar establecer una contraseña de 8 caracteres para el usuario admin_identidad (que requiere 12).
Resultado esperado: El sistema debe rechazar la contraseña por no cumplir con los requisitos de complejidad/longitud.
Evidencia para el reporte: Captura de pantalla del error de complejidad al asignar la contraseña en Active Directory Users and Computers.
Test 3: Flujo de Autenticación de Múltiples Factores (MFA)
Acción: Iniciar sesión en el servidor con credenciales válidas.
Resultado esperado: Tras la contraseña, el sistema debe presentar un campo adicional solicitando el código de Google Authenticator.
Evidencia para el reporte: Fotografía o captura de pantalla de la interfaz de logueo solicitando el token TOTP y captura del dispositivo móvil con el código generado.
Test 4: Bloqueo de Cuenta por MFA Fallido
Acción: Ingresar un código de MFA erróneo 3 veces consecutivas.
Resultado esperado: La cuenta debe quedar bloqueada (Lockout) por 30 minutos.
Evidencia para el reporte: Captura de pantalla del estado de la cuenta en el servidor después de los intentos fallidos (marcada como Locked).
Test 5: Reporte de Auditoría Automatizado (Script)
Acción: Ejecutar el script de PowerShell diseñado para extraer eventos.
Resultado esperado: El script debe generar un archivo .txt o .csv con los últimos 10 intentos de acceso denegado.
Evidencia para el reporte: El archivo de texto resultante adjunto o pegado en el cuerpo del reporte técnico
