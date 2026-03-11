#!/usr/bin/env bash
setGrupos() {
  ###CREACION DE GRUPOS
  if ! getent group "Reprobados" >/dev/null; then
    sudo groupadd Reprobados
  fi

  if ! getent group "Recursadores" >/dev/null; then
    sudo groupadd Recursadores
  fi
  if [[ ! -d /srv/ftp/reprobados ]]; then
    sudo mkdir /srv/ftp/Reprobados
    sudo chown :Reprobados /srv/ftp/Reprobados
    sudo chmod 777 /srv/ftp/Reprobados
  fi
  if [[ ! -d /srv/ftp/recursadores ]]; then
    sudo mkdir /srv/ftp/Recursadores
    sudo chown :Recursadores /srv/ftp/Recursadores
    sudo chmod 777 /srv/ftp/Recursadores
  fi
}

#configuracion del archivo vsftpd.conf
setFtpConf() {
  sudo tee /etc/vsftpd.conf >/dev/null <<EOL
listen=NO
listen_ipv6=YES
anonymous_enable=YES
anon_root=/srv/ftp/Anonymous
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
no_anon_password=YES
local_enable=YES
write_enable=YES
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
chroot_list_enable=YES
chroot_list_file=/etc/vsftpd.chroot_list
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/srv/ftp/\$USER
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO

EOL

  sudo touch /etc/vsftpd.chroot_list
  sudo tee /etc/vsftpd.chroot_list >/dev/null <<EOL
luvbeen
root
EOL

  sudo service vsftpd restart

}

crearUser() {
	local user="$1"
	local grupo="$2"


  sudo useradd $user -d /srv/ftp
  sudo usermod -a -G $grupo $user
  sudo mkdir /srv/ftp/$user
  sudo chown $user:$user /srv/ftp/$user
  sudo mkdir /srv/ftp/$user/$user
  sudo chown $user:$user /srv/ftp/$user/$user
  sudo chmod 500 /srv/ftp/$user
  sudo passwd $user
  sudo mkdir -p /srv/ftp/$user/General
  sudo mount --bind /srv/ftp/General /srv/ftp/$user/General
  sudo chmod 777 /srv/ftp/$user/General
  sudo mkdir -p /srv/ftp/$user/$grupo
  sudo mount --bind /srv/ftp/$grupo /srv/ftp/$user/$grupo
  sudo chmod 777 /srv/ftp/$user/$grupo

}
#funcion para eliminar el usuario
delUser() {
 local user="$1"
 local grupo=$(groups "$user" | awk '{print $NF}')
 sudo umount /srv/ftp/"$user"/General
 sudo umount /srv/ftp/"$user"/"$grupo"
 sudo rm -rf /srv/ftp/"$user"
 sudo userdel "$user"
}
cambiarGrupo() {
  local user="$1"

  # Verificar que el usuario exista
  if ! id "$user" &>/dev/null; then
    echo "El usuario no existe"
    return 1
  fi

  # Obtener grupo actual (el último listado)
  local grupo_actual
  grupo_actual=$(id -nG "$user" | awk '{print $NF}')

  # Determinar nuevo grupo
  local nuevo_grupo
  if [[ "$grupo_actual" == "Reprobados" ]]; then
    nuevo_grupo="Recursadores"
  elif [[ "$grupo_actual" == "Recursadores" ]]; then
    nuevo_grupo="Reprobados"
  else
    echo "El usuario no pertenece a un grupo valido"
    return 1
  fi

  # Quitar bind mount anterior
  sudo umount /srv/ftp/"$user"/"$grupo_actual"
  sudo rm -rf /srv/ftp/"$user"/"$grupo_actual"

  # Cambiar grupo principal y secundarios
  sudo usermod -g "$nuevo_grupo" "$user"
  sudo usermod -G "$nuevo_grupo" "$user"

  # Crear nuevo bind mount
  sudo mkdir -p /srv/ftp/"$user"/"$nuevo_grupo"
  sudo mount --bind /srv/ftp/"$nuevo_grupo" /srv/ftp/"$user"/"$nuevo_grupo"
  sudo chmod 777 /srv/ftp/"$user"/"$nuevo_grupo"

  echo "Usuario $user cambiado a $nuevo_grupo correctamente"
}

