echo "Bienvenido al Servidor de Windows"
echo "nombre del servidor:"
hostname 
echo "direccion ip:"
wmic nicconfig where DHCPEnabled=false get Description,IPAddress
echo "memoria en disco:"
Get-PSDrive C