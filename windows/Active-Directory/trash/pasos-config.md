Cliente y Servidor deben estar en la misma red
    ├── Mismo segmento de red (ej. 192.168.1.x)
    ├── Pueden hacerse ping entre ellos
    └── El cliente puede llegar al servidor
# Desde el cliente
ping 192.168.1.x  # IP del servidor
```

---

## 2. DNS — crítico para AD

El cliente debe apuntar al servidor AD como su DNS. Sin esto el dominio no se resuelve.
```
Cliente Windows 10:
    Configuración de red
        └── DNS primario = IP del servidor AD
            (no 8.8.8.8, no automático)
```

Esto se configura en:
```
Panel de control → Red → Adaptador → IPv4 → DNS manual
```

---

## 3. El servidor debe tener estos roles instalados
```
Active Directory Domain Services  (AD DS)
DNS Server                         ← por eso el cliente apunta al servidor como DNS
```

---

## 4. Credenciales

Necesitas una cuenta con permisos para unir equipos al dominio, normalmente:
```
Usuario: Administrador del dominio

Verificación rápida antes de correr Add-Computer:
# Desde el cliente, verificar que resuelve el dominio
nslookup empresa.local

# Si responde con la IP del servidor = listo
# Si falla = problema de DNS
RESUMEN

