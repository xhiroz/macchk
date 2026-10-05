#!/bin/bash
# Comprobación rápida de un MacBook nuevo antes de pagarlo.
# Uso (en el Terminal del Mac, con internet y el cargador enchufado):
#   curl -fsSL <url-de-este-script> | bash

export LC_ALL=C
# Solo binarios del sistema, que SIP protege: un PATH manipulado no puede colar comandos falsos.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
EXPECT_CHIP="M5 Pro"
EXPECT_MEM="64 GB"
EXPECT_DISK_GB=1000

R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
fails=0; warns=0
ok()   { printf "${G}✅ %s${N}\n" "$1"; }
bad()  { printf "${R}❌ %s${N}\n" "$1"; fails=$((fails+1)); }
warn() { printf "${Y}⚠️  %s${N}\n" "$1"; warns=$((warns+1)); }
title(){ printf "\n${B}%s${N}\n" "$1"; }
# Extrae un valor de un JSON/plist: get "<json>" "ruta.0.clave"
get()  { printf '%s' "$1" | /usr/bin/plutil -extract "$2" raw -o - - 2>/dev/null; }

# Todo va dentro de main para que bash lea el script entero antes de ejecutarlo (curl | bash).
main() {

title "Equipo"
hw=$(system_profiler SPHardwareDataType -json)
name=$(get "$hw" SPHardwareDataType.0.machine_name)
chip=$(get "$hw" SPHardwareDataType.0.chip_type)
mem=$(get "$hw" SPHardwareDataType.0.physical_memory)
serial=$(get "$hw" SPHardwareDataType.0.serial_number)
model=$(get "$hw" SPHardwareDataType.0.model_number)
cores=$(get "$hw" SPHardwareDataType.0.number_processors)
lock=$(get "$hw" SPHardwareDataType.0.activation_lock_status)

[[ $name == *"MacBook Pro"* ]] && ok "Modelo: $name" || bad "Modelo: $name (esperado MacBook Pro)"
[[ $chip == *"$EXPECT_CHIP"* ]] && ok "Chip: $chip" || bad "Chip: $chip (esperado $EXPECT_CHIP)"
[[ $mem == "$EXPECT_MEM" ]] && ok "Memoria: $mem" || bad "Memoria: $mem (esperado $EXPECT_MEM)"
[[ $lock == "activation_lock_disabled" ]] && ok "Bloqueo de activación: desactivado" || bad "Bloqueo de activación: $lock"
cores=${cores#proc }
printf "   Núcleos: %s (compáralo con la ficha de apple.com)\n" "${cores%%:*}"
printf "   macOS: %s\n" "$(sw_vers -productVersion)"

title "Disco"
disk=$(diskutil info -plist disk0)
size=$(get "$disk" Size)
smart=$(get "$disk" SMARTStatus)
gb=$(( ${size:-0} / 1000000000 ))
(( gb > EXPECT_DISK_GB * 95 / 100 && gb < EXPECT_DISK_GB * 105 / 100 )) \
  && ok "Capacidad: $gb GB" || bad "Capacidad: $gb GB (esperado ~$EXPECT_DISK_GB GB)"
[[ $smart == "Verified" ]] && ok "Salud del SSD: $smart" || bad "Salud del SSD: ${smart:-desconocida}"

title "Batería y cargador"
pw=$(system_profiler SPPowerDataType -json)
for i in 0 1 2 3 4 5; do
  c=$(get "$pw" SPPowerDataType.$i.sppower_battery_health_info.sppower_battery_cycle_count)
  [[ -n $c ]] && { cycles=$c
    health=$(get "$pw" SPPowerDataType.$i.sppower_battery_health_info.sppower_battery_health)
    cap=$(get "$pw" SPPowerDataType.$i.sppower_battery_health_info.sppower_battery_health_maximum_capacity); }
  w=$(get "$pw" SPPowerDataType.$i.sppower_ac_charger_watts)
  [[ -n $w ]] && { watts=$w; charging=$(get "$pw" SPPowerDataType.$i.sppower_battery_is_charging); }
  conn=$(get "$pw" SPPowerDataType.$i.sppower_battery_charger_connected)
  [[ -n $conn ]] && connected=$conn
done
cap=${cap//[^0-9]/}
if [[ -z $cycles ]]; then bad "No se pudo leer la batería"
elif (( cycles <= 10 )); then ok "Ciclos de batería: $cycles"
elif (( cycles <= 25 )); then warn "Ciclos de batería: $cycles (algo alto para un Mac nuevo)"
else bad "Ciclos de batería: $cycles (no es nuevo)"; fi
[[ $health == "Good" ]] && ok "Estado de la batería: normal" || bad "Estado de la batería: ${health:-desconocido}"
[[ $cap == 100 ]] && ok "Capacidad máxima: 100 %" || bad "Capacidad máxima: ${cap:-?} % (nueva debe ser 100 %)"
if [[ $connected == "TRUE" || $connected == "true" ]]; then
  ok "Cargador conectado: ${watts:-?} W$([[ $charging == TRUE || $charging == true ]] && echo ', cargando')"
else
  warn "Cargador no conectado: enchúfalo y vuelve a ejecutar para probarlo"
fi

title "Empresa / gestión remota (MDM)"
st=$(profiles status -type enrollment 2>&1)
case $st in
  *"Enrolled via DEP: Yes"*) bad "Inscrito por una empresa (Apple Business Manager)";;
  *"Enrolled via DEP: No"*)  ok "No inscrito por Apple Business Manager";;
  *) bad "No se pudo leer la inscripción en Apple Business Manager: ${st:-sin respuesta}";;
esac
case $st in
  *"MDM enrollment: Yes"*) bad "Tiene gestión remota (MDM)"; grep "MDM server" <<<"$st" | sed 's/^/     /';;
  *"MDM enrollment: No"*)  ok "Sin gestión remota (MDM)";;
  *) bad "No se pudo leer el estado de la gestión remota (MDM)";;
esac

online=$(curl -s -m 8 -o /dev/null -w '%{http_code}' https://www.apple.com)
printf "\n${B}Ahora te pedirá la contraseña de tu usuario (no se ve al escribirla).${N}\n"
if sudo -v; then
  if [[ $online == 2* || $online == 3* ]]; then
    dep=$(sudo profiles show -type enrollment 2>&1)
    if grep -qiE "OrganizationName|ConfigurationURL|IsSupervised" <<<"$dep"; then
      bad "Apple dice que es de una EMPRESA:"; grep -iE "OrganizationName|ConfigurationURL" <<<"$dep" | sed 's/^/     /'
    elif grep -qi "not DEP enabled" <<<"$dep"; then
      ok "Apple responde que no está asignado a ninguna empresa"
    else
      # Cualquier otra respuesta (servidor no disponible, error...) no demuestra nada.
      bad "Apple no ha confirmado que no sea de una empresa. Respuesta:"; head -3 <<<"$dep" | cut -c1-200 | sed 's/^/     /'
    fi
  else
    bad "Sin internet: no se pudo preguntar a Apple si es de una empresa"
  fi
  sp=$(sudo profiles list 2>&1)
  if grep -q profileIdentifier <<<"$sp"; then bad "Hay perfiles de configuración instalados"
  elif grep -qi "no configuration profiles" <<<"$sp"; then ok "Sin perfiles de configuración"
  else warn "No se pudo leer la lista de perfiles: $(head -1 <<<"$sp" | cut -c1-120)"; fi
else
  bad "No se pudo usar sudo: faltan las comprobaciones con contraseña"
fi

title "Rastros de un bypass de gestión remota"
# Los bypass de MDM bloquean los servidores de inscripción de Apple y dejan marcas falsas en el sistema.
hosts=$(grep -vE '^[[:space:]]*(#|$)' /etc/hosts 2>/dev/null)
if grep -qiE 'apple\.com|icloud|mzstatic|aaplimg' <<<"$hosts"; then
  bad "El archivo hosts bloquea servidores de Apple:"; grep -iE 'apple\.com|icloud|mzstatic|aaplimg' <<<"$hosts" | sed 's/^/     /'
else
  extra=$(awk '!($2=="localhost" || $2=="broadcasthost")' <<<"$hosts")
  [[ -z $extra ]] && ok "Archivo hosts de fábrica" || { warn "El archivo hosts tiene entradas añadidas:"; sed 's/^/     /' <<<"$extra"; }
fi
if [[ $online == 2* || $online == 3* ]]; then
  blocked=""
  for h in deviceenrollment.apple.com mdmenrollment.apple.com iprofiles.apple.com; do
    [[ $(curl -s -m 8 -o /dev/null -w '%{http_code}' "https://$h") == 000 ]] && blocked+="$h "
  done
  [[ -z $blocked ]] && ok "Los servidores de inscripción de Apple responden" || bad "No se llega a los servidores de inscripción de Apple: $blocked"
fi
cfg=/var/db/ConfigurationProfiles/Settings
if [[ -e $cfg/.cloudConfigHasActivationRecord || -e $cfg/.cloudConfigRecordFound ]]; then
  bad "El sistema guarda un registro de inscripción de empresa"
elif [[ -e $cfg/.cloudConfigProfileInstalled && $st != *"MDM enrollment: Yes"* ]]; then
  bad "Marca de perfil de empresa instalado sin gestión activa: típico de un bypass"
else
  ok "Sin marcas de inscripción de empresa en el sistema"
fi

title "Seguridad del sistema"
boot=$(system_profiler SPiBridgeDataType -json 2>/dev/null)
sb=$(get "$boot" SPiBridgeDataType.0.ibridge_secure_boot)
# system_profiler traduce este valor al idioma del sistema.
case $sb in
  "Full Security"|"Seguridad máxima") ok "Arranque seguro: $sb";;
  "") warn "No se pudo leer la política de arranque seguro";;
  *[Rr]educ*|*[Pp]ermis*) bad "Arranque seguro rebajado: $sb";;
  *) warn "Arranque seguro: $sb (debería ser el nivel máximo)";;
esac
[[ $(csrutil status) == *"enabled."* ]] && ok "Protección de integridad (SIP): activa" || bad "SIP desactivado"
[[ $(csrutil authenticated-root status) == *"enabled"* ]] && ok "Volumen de sistema sellado: activo" || bad "Volumen de sistema sin sellar"
[[ $(spctl --status 2>&1) == *"assessments enabled"* ]] && ok "Gatekeeper: activo" || bad "Gatekeeper desactivado"

title "Software preinstalado"
ext=$(systemextensionsctl list 2>&1 | head -1)
[[ $ext == "0 extension(s)"* ]] && ok "Sin extensiones de sistema" || { bad "Extensiones de sistema instaladas:"; systemextensionsctl list 2>&1 | tail -n +2 | sed 's/^/     /'; }

agents=$(find /Library/LaunchAgents /Library/LaunchDaemons /Library/PrivilegedHelperTools "$HOME/Library/LaunchAgents" \
  -maxdepth 1 -type f ! -name 'com.apple.*' 2>/dev/null)
[[ -z $agents ]] && ok "Sin programas que arranquen solos" || { bad "Programas que arrancan solos:"; sed 's/^/     /' <<<"$agents"; }

apps=""
for a in /Applications/*.app; do
  id=$(defaults read "$a/Contents/Info" CFBundleIdentifier 2>/dev/null)
  [[ -n $id && $id != com.apple.* ]] && apps+="$(basename "$a") "
done
[[ -z $apps ]] && ok "Solo apps de Apple" || bad "Apps que no son de Apple: $apps"

users=$(dscl . list /Users | grep -vE '^_|^(daemon|nobody|root)$')
others=$(grep -vx "$USER" <<<"$users")
[[ -z $others ]] && ok "Solo existe tu usuario ($USER)" || bad "Hay otros usuarios: $(echo $others)"

title "Señales de uso previo"
now=$(date +%s)
age=$(( (now - $(stat -f %B "$HOME")) / 3600 ))
(( age < 12 )) && ok "Tu usuario se creó hace menos de 12 horas" || warn "Tu usuario se creó hace $age horas"
setup=$(stat -f %B /var/db/.AppleSetupDone 2>/dev/null)
if [[ -n $setup ]]; then
  sage=$(( (now - setup) / 3600 ))
  (( sage < 12 )) && ok "La configuración inicial se hizo hace menos de 12 horas" \
    || warn "La configuración inicial se hizo hace $sage horas: ¿viste tú la pantalla de «Hola»?"
fi
wifi=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
nets=$(networksetup -listpreferredwirelessnetworks "${wifi:-en0}" 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//')
n=$(grep -c . <<<"$nets")
(( n <= 1 )) && ok "Solo recuerda tu red Wi-Fi" || warn "Recuerda $n redes Wi-Fi: $(echo $nets | tr '\n' ' ')"

printf "\n${B}Número de serie: %s${N}\n" "$serial"
printf "${B}Referencia:      %s${N}\n" "$model"
echo "Compara ambos con la etiqueta de la caja y con la factura."
echo
if (( fails == 0 )); then
  printf "${G}${B}✅ TODO CORRECTO${N}"; (( warns )) && printf " ${Y}(%d aviso(s): léelos arriba)${N}" "$warns"; echo
else
  printf "${R}${B}❌ %d PROBLEMA(S): NO PAGUES hasta aclararlo${N}\n" "$fails"
fi
}

main "$@"
