echo Bienvenido al servidor de Ubuntu !
echo El nombre del equipo es:
hostname
echo la ip del equipo es:
ip -4 address show enp0s8 | grep 'inet' 
echo Informacion de memoria en disco:
df -h /
