## Conceptos Clave de la practica
>[!INFO] RBAC (Role-Based Acces Control)
>Se definen roles con responsabilidades claras y asignas
>usuarios a esos roles. Principio de minimo priovilgeio: cada quien solo puede hacer lo de su rol.
>
>

>[!INFO] ACL(Lista de Control de Acceso)
>Es la herramienta tecnica que hace posible el RBAC en AD, Cada
>objeto(usuario, OU,GPO) tiene una lista que dice quien puede leer,
>escribir, borrar, etc. - y tambien quien tiene explicitamente denegado
>algo

>[!INFO] FGPP (Fine-Grained Password Policy)
>AD normalmente tiene una sola politica de contraseñas para todo el dominio,
>FGPP permite tener politicas distintas por grupo. Los admins necesitan
>contraseñas mas fuertes que los usuarios normales

>[!INFO] Auditoria de eventos
>Windows puede registrar cada intento de login, acceso a archivos,
>cambio de politica, etc. El evento 4625 especificamente es "inicio de sesion fallido"
>Sin auditoria activada, estos eventos simplemente no se guardan.

>[!INFO] MFA/TOTP
>Autenticacion de dos factores donde el segundo factor es un codigo de 6
>digitos que cambia cada 30 segundos. Esta basado en tiempo + una clave secreta
>compartida entre el servidor y la app (Google Authenticator). Aunque alguen 
>robe tu contraseña normal con LSASS, luego exige el codigo TOTP antes de dejar pasar.

# Relacion de todo
### Usuario intenta entrar al servidor
            |
            v
### Credential Provider con MFA
            |
            |
            v
#### Pide contraseña -> LSASS la valida contra AD
#### Pude codigo TOTP -> Lo verifica contra el algoritmo TOTP
#### 3 fallos = bloqueo 30 min (FGPP / lockout policy)
         |
         V
Usuario entra al sistema
         |
         V
    Quiere hacer una accion (ej. resetear contraseña)
         |
         v
### Active directory revisa las ACLs del objeto
     --> TIene permiso su rol? -> Si: ejecuta accion
         |                        No: "Acceso denegado" -> genera evento 4625/4656
         |
         V
    Script de auditoria
    Extrae los ultimos 10 eventos de acceso denegado ->archivo.txt
    admin auditoria puede leer ese reporte (solo lectura)












