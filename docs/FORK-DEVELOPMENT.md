# Fork development integration

The fork combines focused upstream contributions in one integration branch. Each contribution keeps its own upstream PR. The integration uses committed source revisions instead of applying a separate patch queue.

## Source inputs

| Component | Revision | Scope |
|---|---|---|
| Upstream `development` | `d36249952131f49aa21a97681b4f0ffbf5556688` | Current launcher, setup, USB, window, and Linux compatibility work |
| [PR31](https://github.com/YahiaAngelo/vphone-linux/pull/31) | `cb84e421a61a761d4f94b989c3ce3776eb08eb37` | Staged dyld cache publication, durable receipts, and recovery |
| [PR48](https://github.com/YahiaAngelo/vphone-linux/pull/48) | `6e463f5eb25afcfccc08953c9da03af5bb502a7b` | Linux adapters for shared DriverKit and restore-TXM helpers |
| [PR54](https://github.com/YahiaAngelo/vphone-linux/pull/54) | `5a6206130d039799ba5a7a07b6797522011b4cd7` | Idempotent scale changes and bounded FrontBoard readiness |
| [PR59](https://github.com/YahiaAngelo/vphone-linux/pull/59) | `06e77a3678852d050a4bf0f158b986ae6d81cefb` | Native CoreFoundation identities and Linux timestamps |
| CLI source | `2daeabc5e945d87ebc9eef3b51a6511998e423be` | Upstream `37ab6271` with separate CLI contributions 872, 876, 878, and 879 |

The CLI source retains its pinned dependency graph, including Icli `2fbdb5ee61d8c320732deb9768b22506f5e3d411`. It does not include the separate Icli active-geometry contribution in PR19.

## Build the Linux host tools

Use a separate, clean CLI checkout at the exact source revision above. An explicit `VPHONE_CLI` directory is caller-owned. The source selector does not change or validate that directory's revision.

Install the matching development headers and libraries before building. The validated private dependency prefix used libimobiledevice `1.4.0` at `149f7623c672c1fa73122c7119a12bfc0012f2ac`. Its installed `libimobiledevice/restore.h` and library matched the same source build. A runtime library alone does not provide the required header.

If the dependencies use a private prefix, select it explicitly for compilation and linking. The runtime path lets the resulting executable find those libraries without `LD_LIBRARY_PATH`.

```sh
set -euo pipefail
export VPHONE_CLI=/absolute/path/to/separate/vphone-cli-checkout
export VPHONE_CLI_REF=2daeabc5e945d87ebc9eef3b51a6511998e423be
test -z "$(git -C "$VPHONE_CLI" status --porcelain)"
git -C "$VPHONE_CLI" switch --detach "$VPHONE_CLI_REF"
test "$(git -C "$VPHONE_CLI" rev-parse HEAD)" = "$VPHONE_CLI_REF"

dependency_prefix=/absolute/path/to/compatible-host-dependencies
export CPATH="$dependency_prefix/include"
export PKG_CONFIG_PATH="$dependency_prefix/lib/pkgconfig"
export LIBRARY_PATH="$dependency_prefix/lib"
export LD_LIBRARY_PATH="$dependency_prefix/lib"
test -r "$dependency_prefix/include/libimobiledevice/restore.h"
pkg-config --exists libimobiledevice-1.0 libimobiledevice-glue-1.0 \
  libplist-2.0 libusbmuxd-2.0 libtatsu-1.0 libirecovery-1.0

VPHONE_SWIFT_LLD=1 ./linux-create/build.sh --configuration release --jobs 2 \
  -Xcc "-I$dependency_prefix/include" \
  -Xlinker "-L$dependency_prefix/lib" \
  -Xlinker -rpath -Xlinker "$dependency_prefix/lib"

product=linux-create/.build/out/out/Products/Release-linux-$(uname -m)/vphone-cli
test -x "$product"
env -u LD_LIBRARY_PATH ldd "$product"
env -u LD_LIBRARY_PATH "$product" --help
```

Check that `ldd` resolves the mobile-device libraries from the selected prefix and reports no missing libraries. This recipe uses the installed Swift `6.4.1` toolchain and LLD. The build helper can install Swift if it is absent.

The wrapper prefers the Release product. If only a Debug product exists, it reports that fallback. Record the selected product and source revision when reporting a build result.

CLI source selection and guest resources are separate inputs. The default `VPHONE_CLI_PUBLIC=2.14.2` is unchanged. This integration needs guest resources built from the matching CLI candidate before native validation. A successful Linux Release build validates the host tooling. It does not validate an Apple bundle, SSH ramdisk boot, guest boot, or input.

## Legacy source disposition

The previous fork `dev` at `909f3a61cf02d5b40b265a5e4e534730bc39ab25` remains in the integration ancestry. Its source changes have the following owners. An ancestry merge records this relationship without replacing the current integration tree with the prototype tree.

| Legacy commits | Current disposition |
|---|---|
| `65e7f5b`, `4b89ae3`, `63220bf`, `bfd5406`, `cba658e`, `4e9add5`, `ac0b585`, `ea6d363`, `308e153`, `6ad482e`, `4472c1e`, `0789bfd`, `6ccd032`, `89a7c76`, `097afbe`, `04a8f6c` | Patch-equivalent changes are already in upstream `development`. |
| `14cdac6`, `f4640db` | PR27 and the native first-boot QMP setting retain the launcher behavior and its regression. |
| `4793b47`, release and CI parts of `b07298f` | PR30 retains Release selection and the explicit Debug fallback. Current CI covers the selected product. |
| `4511fd8`, `30c3dd4` | PR29 retains native window controls, socket overrides, and Duo detection. Upstream also handles unavailable Home lock state. |
| `9e08938`, `3981faa` | PR43 binds CFW connections to the selected VM. PR31 also uses that connection for the final guest synchronization. |
| `bc71c3b` | Upstream retains native `VPHONE_*` caller settings, private helper readiness, trace permissions, and caller regressions. |
| `e98bfb5` | PR44 retains the private Swiftly installation and configured binary directory. |
| `b700683` | PR46 retains the configurable CFW work parent. |
| `af663a0`, `f405236`, `037101a`, `bb84811`, `909f3a6` | PR47 makes the ECID-aware bootstrap an explicit choice and tests that binding. PR42 rejects mismatched explicit identities. Upstream intentionally permits a sole stock SSH ramdisk with no ECID in its serial. |
| `46163f7`, `1d46c78`, `33ea973` | Current PR31 retains incremental updates, strict cache audit, durable synchronization, pending-publication boot fences, and explicit recovery. |
| `1058a90`, `77b38c3`, `04968be` | The prototype added and then removed backend rewrites after recovery-client cleanup and display geometry moved into the CLI. Their final backend change is empty. |
| `3d667f2`, `d16bd5f`, migration-policy tests in `b07298f` | The caller owns strict expected-build DataMigrator acceptance. Its [creator verification](https://github.com/bvolpato/limulator/blob/8b7e753d4f261cf4e87218349aff0d2afa43a645/src/limulator/creator.py#L1181) and regression tests retain that policy. The integration preserves upstream's normal-boot definition and unlimited default migration wait. |

## Validation boundaries

Setup smoke tests and mock transport tests validate source integration without booting a guest. The cache transaction harness validates the production staging and recovery code on host fixtures. Restore-TXM tests use private copies when the documented fixture is supplied.

Native acceptance needs the matching CLI and guest-resource tuple, the intended QEMU and GPU dependencies, and an isolated VM copy. Keep native results separate from compilation, mock checks, cache format audits, and upstream review status.
