#Que es active directory?
Active Directory es un servicio de directorio desarrollado por Microsoft que funciona como el sistema central de gestión de identidades y accesos en una red empresarial. Fue introducido con Windows Server 2000 y sigue siendo la columna vertebral de la mayoría de infraestructuras corporativas Windows.
#¿Que problema resuelve?
Sin AD, cada servidor o recurso tendría que gestionar sus propios usuarios y contraseñas por separado. AD centraliza todo eso: un solo lugar para gestionar quién es quién y quién puede hacer qué en toda la red.
#Conceptos clave
##Dominio: La unidad base. Agrupa usuarios, equipos y recursos bajo una misma politica de seguridad, Ejemplo: empresa.local
Domain Controller: El servidor corre Active Directory. Es el cerebro: autentica usuarios, aplica politicas y alamcena el directorio. En produccion siempre se tienen al menos dos para redundancias.
Objetos: Tood en AD es un objeto: usuarios, grupos equipos, impresoras, politicas. Cada objeto tiene atributos(nombre, correo, departamento, etc.).
OU(organization unit): Carpetas lógicas dentro del dominio para organizar objetos. Ejemplo: OU=Finanzas, OU=TI. Permiten aplicar politicas especificas por area.
GPO(Group Policy Object): Politicas que se aplican automaticament. Ejemplo: Forzar fondo de pantalla corporativo, bloquear USB, configurar firewall mapear unidades de red.
LDAP: El protocolo que usa AD(Active Directory) para consultar y modificar el directorio. Muchas aplicaciones (como sistemas de tickets)se integran via LDAP para autenticación.
Kerbos El protocolo de autenticacion que usa AD por defecto. Basado en tickets, es mas seguro que enviar contraseñas por la red.
Example that 
