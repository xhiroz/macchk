# macchk

Comprobación rápida de un MacBook nuevo antes de pagarlo: chip, memoria, disco, batería, Bloqueo de activación, gestión remota de empresa (MDM / Apple Business Manager), perfiles, seguridad del sistema y software preinstalado.

Con el Mac recién configurado (usuario local, sin Apple ID), conectado a internet y con el cargador enchufado, abre Terminal y ejecuta:

```bash
curl -fsSL raw.githubusercontent.com/xhiroz/macchk/main/check.sh | bash
```

Pedirá la contraseña del usuario para las comprobaciones de empresa. Al final dice **TODO CORRECTO** o cuántos problemas hay.

Los valores esperados (chip, memoria, disco) están al principio de `check.sh`.
