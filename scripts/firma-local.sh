#!/bin/bash
# Crea, una sola vez, la identidad de firma «Margin Local» en el llavero de inicio de sesión.
#
# Por qué: firmada ad hoc, cada compilación tiene otra identidad y macOS puede olvidar los permisos que le diste a
# Margin (acceso total al disco, notificaciones). Firmada siempre con el mismo certificado, macOS la reconoce entre
# versiones. Es un certificado propio que solo existe en este Mac: no hace falta cuenta de desarrollador de Apple, no
# se marca como de confianza ni se toca la configuración de seguridad del sistema.
#
# La clave privada se genera en una carpeta temporal, se importa al llavero (solo `codesign` puede usarla sin
# preguntar) y se borra del disco.
set -euo pipefail
name="Margin Local"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "La identidad «$name» ya existe."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$work/clave.pem" -out "$work/cert.pem" -subj "/CN=$name" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
# Contraseña de un solo uso para el paquete temporal; nunca se guarda.
pass="$(openssl rand -hex 24)"
# Cifrado PKCS#12 clásico: el que acepta `security import`.
openssl pkcs12 -export -inkey "$work/clave.pem" -in "$work/cert.pem" -name "$name" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -out "$work/firma.p12" -passout "pass:$pass"
security import "$work/firma.p12" -k "$keychain" -f pkcs12 -P "$pass" -T /usr/bin/codesign >/dev/null
echo "Creada la identidad «$name» en el llavero de inicio de sesión."
