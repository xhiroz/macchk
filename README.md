# macchk

Comprobación rápida de un MacBook nuevo antes de pagarlo: chip, memoria, disco, batería, Bloqueo de activación, gestión remota de empresa (MDM / Apple Business Manager), perfiles, seguridad del sistema y software preinstalado.

Con el Mac recién configurado (usuario local, sin Apple ID), conectado a internet y con el cargador enchufado, abre Terminal y ejecuta:

```bash
curl -fsSL raw.githubusercontent.com/xhiroz/macchk/main/check.sh | bash
```

Pedirá la contraseña del usuario para las comprobaciones de empresa. Al final dice **TODO CORRECTO** o cuántos problemas hay.

Los valores esperados (chip, memoria, disco) están al principio de `check.sh`.

## Qué comprueba además

- Que la respuesta de Apple sobre la asignación a una empresa sea explícita: un error del servidor no cuenta como "limpio".
- Rastros de un bypass de gestión remota: servidores de Apple bloqueados en el archivo `hosts` y marcas `.cloudConfig*` falsas.
- Política de arranque seguro y fecha de la configuración inicial.

## Fuentes

Ideas y salidas de ejemplo tomadas de [Tirekick](https://github.com/everydayopen/tirekick) (MIT), cuyas muestras de `profiles show -type enrollment` sirven para probar este script, y de [bypass-mdm](https://github.com/assafdori/bypass-mdm) (MIT), que documenta qué deja un bypass en el sistema.
