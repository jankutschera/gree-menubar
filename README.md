# AC: Gree air conditioner in your Mac menu bar

A small native macOS menu bar app (SwiftUI) that controls Gree / Gree+ air conditioners
over your local network. No cloud account, no Gree+ app, no dependencies.

- Power, target temperature (16–30 °C), mode, fan speed, sleep, eco, vertical airflow
- Turbo, quiet, display light, health, X-Fan, left/right swing
- Room temperature from the unit's own sensor
- Left-click the icon for the panel, right-click for Quit
- Hover any button for a short explanation

## Requirements

- macOS 14+, Xcode command line tools (Swift 5.9+)
- The AC on the same network as your Mac (UDP port 7000)

## Build and run

```sh
./build.sh
open build/AC.app
```

macOS asks for Local Network access on first launch. Allow it.

The app finds the unit by broadcast. To skip discovery: `GREE_IP=192.168.x.x build/AC.app/Contents/MacOS/AC`.

Debug helpers:

```sh
build/AC.app/Contents/MacOS/AC --status                    # print live state
build/AC.app/Contents/MacOS/AC --status --set SetTem=23    # send one command
build/AC.app/Contents/MacOS/AC --snapshot panel.png        # render the panel to PNG
```

## How it works

Gree units answer a JSON-over-UDP protocol on port 7000: `scan` to discover, `bind` to get a
device key, then `status` / `cmd`. Newer firmware encrypts with AES-GCM, older with AES-ECB;
this app uses GCM (tested on GWH12AWBXB-K6DNA3F, firmware V3.4.M, where scan replies are ECB
but bind and control need GCM). Protocol work builds on
[tomikaa87/gree-remote](https://github.com/tomikaa87/gree-remote) and
[greeclimate](https://pypi.org/project/greeclimate/).

## Status

Tested on one unit. Reading state, target temperature and the controls in the panel work there;
some features (eco, X-Fan, horizontal swing) depend on the model. Fan speeds are limited to
Auto/Low/Medium/High, and temperature to whole degrees.

Not affiliated with Gree. MIT licensed (see LICENSE).
