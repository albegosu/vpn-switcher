> 🌐 **English:** [README.md](README.md) · **Español:** este documento

<p align="center">
  <img src="assets/logo.png" alt="VPN Switcher" width="128" height="128">
</p>

# VPN Switcher

**Una barra de menús para la VPN de cada cliente** — cuentas de Tailscale,
túneles WireGuard, VPN nativas de macOS y cualquier cosa con CLI.

Si haces malabares con las VPNs de varios clientes —unas cuantas cuentas de
Tailscale, algún túnel WireGuard, una IKEv2 corporativa— acabas saltando de
app en app: el menú de Tailscale para las tailnets, la app de WireGuard para
los túneles, Ajustes del Sistema para el resto. VPN Switcher las junta todas en
**una sola barra de menús**, agrupadas por provider, una activa a la vez.

El truco: no sabe nada de VPNs concretas. Cada perfil son tres comandos de
shell (activar / desactivar / estado) en un YAML declarativo, así que maneja
cualquier cosa scriptable — fast-switching de Tailscale, WireGuard vía
`scutil`, VPN nativas, Mullvad, Cloudflare WARP, OpenVPN… Añadir un cliente es
un bloque, no una app nueva. Atajos globales y un panel rápido estilo Spotlight
encima.

## Capturas

<p align="center">
  <img src="assets/menu.png" alt="Menú agrupado por provider" width="440"><br>
  <em>Perfiles agrupados por provider, ✓ en el activo, atajos a la derecha.</em>
</p>

<p align="center">
  <img src="assets/quick-switch.png" alt="Panel de cambio rápido" width="520"><br>
  <em>El panel rápido (⌃⌥V): escribe para filtrar, ↑↓ para moverte, Enter para cambiar.</em>
</p>

<sub>Datos de demo — empresas ficticias, no clientes reales.</sub>

## Instalación

VPN Switcher se compila desde el código. Un build local va firmado ad-hoc y sin
cuarentena, así que arranca sin avisos de Gatekeeper. Un solo comando:

```sh
git clone https://github.com/albegosu/vpn-switcher.git
cd vpn-switcher
./install.sh
```

`install.sh` comprueba Xcode, instala [XcodeGen](https://github.com/yonaskolb/XcodeGen)
por Homebrew si hace falta, compila, instala en `/Applications` (o
`~/Applications`) y lanza la app. Luego clic en el escudo de la barra →
**Create example config** y edita `~/.config/vpn-switcher/profiles.yaml`
(recetas en [PROVIDERS.md](PROVIDERS.md)).

**Requisitos:** macOS 15+ y Xcode 16+. (XcodeGen se instala solo si tienes
[Homebrew](https://brew.sh).)

## Cómo funciona

Todo es declarativo: la app lee `~/.config/vpn-switcher/profiles.yaml` y
cada perfil define su nombre, su provider (solo para agrupar en el menú) y
tres comandos:

```yaml
profiles:
  - name: Client A
    provider: tailscale
    activate_cmd: tailscale switch client-a.example.ts.net ; tailscale up --accept-routes
    deactivate_cmd: tailscale down
    status_cmd: s=$(tailscale status --json); echo "$s" | grep -q '"BackendState": "Running"' && echo "$s" | grep -A1 '"CurrentTailnet"' | grep -q '"Name": "client-a.example.ts.net"'

  - name: Client C
    provider: wireguard
    activate_cmd: scutil --nc start "client-c-tunnel"
    deactivate_cmd: scutil --nc stop "client-c-tunnel"
    status_cmd: scutil --nc status "client-c-tunnel" | head -1 | grep -qx Connected
```

Añadir un cliente nuevo = añadir un bloque, sin tocar código. La plantilla
completa está en [profiles.example.yaml](profiles.example.yaml) (el botón
"Create example config" del menú escribe la misma), y en
[PROVIDERS.md](PROVIDERS.md) tienes recetas listas para Tailscale, WireGuard,
VPN nativas de macOS (IKEv2/IPsec), Mullvad, Cloudflare WARP y OpenVPN.

- **Contrato del `status_cmd`**: exit 0 = perfil activo, exit 1 = inactivo,
  cualquier otro código = error (se muestra en la fila). Es la convención
  natural de `grep -q` y `test`.
- **Estado real, no el del último clic**: la app sondea los `status_cmd`
  cada `poll_interval` segundos (10 por defecto). Si cambias de VPN desde
  el terminal, el menú lo refleja en el siguiente sondeo.
- **Exclusividad global (una sola VPN a la vez)**: al activar un perfil, se
  ejecuta antes el `deactivate_cmd` de **cualquier** otro perfil activo que
  lo declare, sea del provider que sea. Un perfil sin `deactivate_cmd` se
  deja como está. Así activar un túnel WireGuard baja las tailnets de
  Tailscale y viceversa. (Entre dos tailnets el cambio pasa por un `down`+`up`
  rápido; si prefieres que Tailscale conviva con WireGuard, quítale el
  `deactivate_cmd`.)
- **Toggle**: activar un perfil que ya está activo lo desactiva (ejecuta su
  `deactivate_cmd`).
- Los comandos corren con `/bin/sh -c` y el PATH de Homebrew por delante
  (`/opt/homebrew/bin:/usr/local/bin`), porque una app lanzada desde Finder
  no hereda el PATH de tu shell.

## Atajos de teclado globales

También declarativos. Cada perfil puede llevar un `hotkey:` que lo activa
desde cualquier app, y a nivel raíz `disconnect_all_hotkey:` corta todas
las VPNs activas que declaren `deactivate_cmd`:

```yaml
disconnect_all_hotkey: ctrl+opt+0
quick_switch_hotkey: ctrl+opt+v

profiles:
  - name: Client A
    provider: tailscale
    hotkey: ctrl+opt+1
    ...
```

`quick_switch_hotkey` abre un **panel flotante de cambio rápido** (estilo
Spotlight/Quick Access de 1Password): escribe para filtrar por nombre o
provider, flechas ↑↓ para moverte, Enter activa el seleccionado, Esc (o un
clic fuera) cierra.

- Formato: modificadores + tecla separados por `+`. Modificadores: `cmd`,
  `opt` (o `alt`), `ctrl`, `shift`; tecla: letra, dígito, `space` o
  `f1`–`f12`. Se exige al menos un modificador que no sea shift.
- Los atajos aparecen en el menú junto a cada perfil. Si otro programa ya
  posee un atajo **global**, el sistema rechaza el registro y el menú lo
  avisa — no se roba el atajo. Ojo con el caso contrario: un atajo global
  registrado con éxito **tapa ese combo en todo el sistema**, incluidos los
  atajos locales de otras apps (p. ej. `cmd+shift+v` = pegar sin formato en
  muchos editores). Elige combos que no uses: `ctrl+opt+<tecla>` suele
  estar libre.
- Implementado con `RegisterEventHotKey` (Carbon): sin dependencias y sin
  pedir permisos de Accesibilidad, a diferencia de los monitores globales
  de eventos.

## WireGuard

### Recomendado: la app oficial de WireGuard (sin sudo)

Instala la [app oficial de WireGuard](https://apps.apple.com/app/wireguard/id1451685025)
(App Store), importa ahí el `.conf` del túnel, y deja que VPN Switcher lo
active con `scutil --nc`. Es el equivalente *headless* del botón "Activate":
habla con la misma Network Extension de Apple, así que **no necesita `sudo`,
ni `wg-quick`, ni manipular el `.conf`**, y **no ejecuta los hooks
`PreUp`/`PostUp`** del túnel. El nombre debe coincidir exactamente con el que
muestra `scutil --nc list`.

Esto mismo sirve para **cualquier VPN nativa de macOS** (IKEv2, IPsec, L2TP)
configurada en Ajustes del Sistema. Ver recetas en [PROVIDERS.md](PROVIDERS.md).

### Alternativa: `wg-quick` crudo (solo si NO usas la app)

`wg-quick` necesita root y **ejecuta los `PreUp`/`PostUp` del `.conf` como
root**, así que solo úsalo con túneles cuyo `.conf` hayas revisado. Requiere
una entrada de sudoers `NOPASSWD` acotada a `wg-quick`. Ojo: en Apple Silicon
`/opt/homebrew` es escribible por tu usuario, con lo que `NOPASSWD` sobre un
binario de Homebrew permitiría escalar a root a algo que ya corra como tú.
Cerrarlo del todo exige copiar `wg-quick` **y** sus dependencias (`wg`,
`wireguard-go`) a un directorio root-only y apuntar sudoers ahí. Para casi
todos los casos, la app oficial es más simple y más segura.

Coloca siempre el `.conf` root-owned (`sudo chown root:wheel`, `chmod 600`),
nunca en el repo.

## Seguridad

Modelo de amenaza en corto: la app no es una frontera de seguridad — es un
envoltorio al mismo nivel de confianza que tu cuenta de usuario. Con el
método recomendado (Tailscale por CLI + WireGuard vía la app oficial), **no
hay ningún comando con privilegios**: todo corre como tu usuario. `sudo` solo
aparece si eliges la alternativa `wg-quick`, y ahí es la única frontera de
privilegio (revísala tú).

- **Las claves privadas de WireGuard de clientes NUNCA van a este repo.** Con
  la app oficial ni siquiera pasan por VPN Switcher (viven en el llavero de
  la app). Si usas `wg-quick`, el `.conf` va root-owned fuera del repo. El
  `.gitignore` bloquea además `profiles.yaml` y `*.conf` por si alguno acaba
  aquí por error. La app no lee claves ni credenciales, no hace conexiones de
  red propias y no tiene telemetría.
- **`profiles.yaml` es código, no datos**: cada perfil es un comando que la
  app ejecuta con tus permisos. La app lo crea con permisos `600` (y el
  directorio `700`) y **se niega a cargarlo si otros usuarios pueden
  escribirlo**. Quien pueda escribir ese fichero ejecuta código como tú —
  el mismo nivel de confianza que tu `.zshrc`.
- **Sin sandbox, sin hardened runtime, firma ad-hoc**: deliberado (la app
  ejecuta binarios externos); es una utilidad personal sin distribución.
  No instales builds de terceros: compílala tú con `make build`.

## Requisitos

- macOS 15+
- Xcode 16+ (para compilar)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Compilar y ejecutar

```sh
make gen    # regenera VPNSwitcher.xcodeproj desde project.yml
make build  # compila con xcodebuild
make run    # compila y lanza la .app
make test   # ejecuta la suite de tests
make typecheck  # verificación rápida de tipos sin Xcode (solo CLT)
```

El `.xcodeproj` no se versiona: la definición del proyecto vive en
`project.yml`.

## Notas de diseño

- SwiftUI `MenuBarExtra` (estilo window), Swift 6 con concurrencia estricta,
  un actor (`SwitchEngine`) que sondea y ejecuta, y un `AppState` observable
  en el MainActor como única fuente de verdad de la UI.
- **Cero dependencias de paquetes**: el YAML lo parsea un parser propio del
  subconjunto necesario (`ProfilesConfigParser`, testeado).
- **Sin App Sandbox**: la app ejecuta binarios externos y lee `~/.config`.
- **El switch sobrevive al menú**: la activación corre en un Task del actor,
  no de la vista — cerrar el menú a mitad no aborta el cambio a medias.

## Alternativas y prior art

El nicho de VPN Switcher es orquestar **muchos providers distintos** desde una
config declarativa. Si ese no es tu caso, quizá te encaje mejor alguna de
estas —y conviene conocerlas:

- **[vpn-bar](https://github.com/borzov/vpn-bar)**, **[vipinator](https://github.com/vpukhanov/vipinator)** (MIT, archivada) y **VPNStatus/vpnutil** (Timac) — togglers de VPN nativa en la barra. Ideales si todas tus VPN están en Ajustes del Sistema (IKEv2/IPsec/L2TP); no cambian de cuenta Tailscale, ni levantan WireGuard, ni ejecutan comandos propios.
- **[SwiftBar](https://github.com/swiftbar/SwiftBar) / [xbar](https://xbarapp.com)** — cualquier script en la barra. La misma idea de "una VPN son comandos", pero como lienzo en blanco: la agrupación, la exclusividad y la UI las montas tú. VPN Switcher es esa idea, ya hecha.
- **[Shimo](https://www.shimovpn.com/)**, **[Viscosity](https://www.sparklabs.com/viscosity/)** — clientes multi-protocolo comerciales y pulidos. De pago y cerrados, basados en protocolos (no en comandos), y permiten conexiones simultáneas en vez de una-a-la-vez.
- **Tailscale**, **WireGuard**, **Mullvad**, **Proton**… — excelentes cada uno para su red. VPN Switcher no los reemplaza; los maneja desde un solo sitio.
- **[TailMux](https://tailmux.app/)** (varias tailnets *a la vez*) y **[VPN-Bypass](https://github.com/GeiserX/VPN-Bypass)** (split-tunnel) resuelven problemas vecinos, distintos.

Lo único aquí: providers heterogéneos vía comandos arbitrarios, config
declarativa, exclusividad "una VPN a la vez" entre providers, y panel de cambio
rápido — open source y sin dependencias.

## Licencia

[MIT](LICENSE).
