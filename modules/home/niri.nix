{ pkgs
, lib
, config
, ...
}:
let
  cfg = config.wayland.windowManager.niri;

  # Nullscapes palette (theme/nullscapes.nix), the source of every color in
  # the visual block below.
  p = config.theme.nullscapes.dark;

  # 4K-class outputs (a TV, typically) get scale 2. niri's own scale guess
  # (src/utils/scale.rs, Mutter's heuristic) lands on 1.0 for the 1080p
  # laptop panel and 1080p/1440p desktop monitors, which is what those want,
  # but also on 1.0 for a large 4K TV (~80 PPI), where the 1080p-sized UI is
  # unreadable at couch distance. niri config matches outputs only by
  # connector or make/model/serial, so the rule is applied over IPC instead,
  # matched on the current mode's pixel size so it does not depend on which
  # port the TV is on. niri has no output-added event; every output change
  # re-lays out workspaces, so WorkspacesChanged is the trigger. An output is
  # scaled once per connection: a manual `niri msg output <name> scale …`
  # afterwards sticks, and a replugged output is scaled again.
  scaleLargeOutputs = pkgs.writeShellApplication {
    name = "niri-scale-4k-outputs";
    runtimeInputs = [ cfg.package pkgs.jq ];
    text = ''
      declare -A handled=()

      apply() {
        local outputs name
        outputs="$(niri msg --json outputs)" || return 0
        for name in "''${!handled[@]}"; do
          if ! jq -e --arg n "$name" 'has($n)' <<<"$outputs" >/dev/null; then
            unset "handled[$name]"
          fi
        done
        while IFS= read -r name; do
          if [ -z "$name" ] || [ -n "''${handled[$name]:-}" ]; then
            continue
          fi
          handled[$name]=1
          niri msg output "$name" scale 2 || true
        done < <(jq -r '
          to_entries[].value
          | select(.current_mode != null)
          | select(.modes[.current_mode].width >= 3840 and .modes[.current_mode].height >= 2160)
          | .name
        ' <<<"$outputs")
      }

      apply
      while IFS= read -r event; do
        case "$event" in
          '{"WorkspacesChanged"'*) apply ;;
        esac
      done < <(niri msg --json event-stream)
    '';
  };
in
{
  # niri Home Manager config, via home-manager's built-in
  # `wayland.windowManager.niri` module (modules/services/window-managers/
  # niri.nix). The system side, modules/nixos/gui/niri.nix (and
  # modules/nixos/console/desktop.nix on the console), installs niri and its
  # systemd user units and registers the session, so here:
  #   - systemd.enable = false: niri.service / niri-shutdown.target already
  #     come from the system profile (programs.niri sets systemd.packages).
  #   - portalPackage = null: programs.niri already configures the portals.
  #   - xwaylandSatellitePackage keeps its default: niri has no built-in
  #     XWayland and starts xwayland-satellite on demand from PATH (Steam and
  #     other X11 clients need it); programs.niri does not install it.
  #   - checkConfig keeps its default (on): the generated config.kdl is run
  #     through `niri validate` at build time.
  #
  # Keymap: the previous Hyprland keymap carried over bind for bind (terminal,
  # close, lock, focus, workspaces, Noctalia shell verbs, media and brightness
  # keys), plus niri's scrollable-tiling column binds.
  #
  # Locking and idle are Noctalia's (modules/home/noctalia.nix,
  # modules/home/idle.nix). Laptop lid: niri itself turns the internal panel
  # off while the lid is closed and another output is connected, and back on
  # when it opens (should_disable_laptop_panels, src/backend/tty.rs); with no
  # other output, logind's HandleLidSwitch suspends
  # (configurations/nixos/laptop/power.nix). No lid config is needed here.
  #
  # Visual layer (blur, gradient focus ring, shadows, rounded corners, tab
  # indicator, overview backdrop, animations and the Noctalia layer rules) is
  # ported from triplespike/Spike-dotfiles home.nix (rev 3cf70b7d), with its
  # hard-coded Nullscapes hexes read from theme/nullscapes.nix instead. Its
  # per-app rules are ported only for apps installed here: kitty stands in for
  # its ghostty (translucent terminal, blurred), the Firefox/Vesktop/Spotify
  # rules depend on that repo's userChrome/quickCss/Spicetify transparency and
  # are not ported, nor are its window-placement, monitor and keyboard-layout
  # settings.
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    wayland.windowManager.niri = {
      enable = true;
      systemd.enable = false;
      portalPackage = null;

      extraConfig = ''
        input {
            keyboard {
                numlock
            }
            touchpad {
                tap
                natural-scroll
            }
        }

        prefer-no-csd

        hotkey-overlay {
            skip-at-startup
        }

        spawn-at-startup "${lib.getExe scaleLargeOutputs}"

        cursor {
            xcursor-theme "${config.home.pointerCursor.name}"
            xcursor-size ${toString config.home.pointerCursor.size}
        }

        blur {
            passes 2
            offset 1.5
        }

        layout {
            gaps 16
            center-focused-column "never"
            background-color "transparent"

            preset-column-widths {
                proportion 0.25
                proportion 0.5
                proportion 0.75
                proportion 1.0
            }

            focus-ring {
                width 2.5
                active-gradient from="${p.mPrimary}" to="${p.mTertiary}" angle=135 relative-to="workspace-view"
                inactive-color "transparent"
            }

            tab-indicator {
                hide-when-single-tab
                place-within-column
                gap 6
                width 4
                length total-proportion=0.85
                position "top"
                active-gradient from="${p.mPrimary}" to="${p.mTertiary}" angle=90
                inactive-color "${p.mSurfaceVariant}88"
                corner-radius 6
            }

            shadow {
                on
                softness 42
                spread 5
                offset x=0 y=10
                color "#050711cc"
            }

            struts {
                left 10
                right 10
                top 8
                bottom 10
            }
        }

        overview {
            backdrop-color "${p.terminal.background}dd"
            workspace-shadow {
                on
            }
        }

        animations {
            horizontal-view-movement {
                spring damping-ratio=0.84 stiffness=820 epsilon=0.0001
            }
            window-movement {
                spring damping-ratio=0.82 stiffness=800 epsilon=0.0001
            }
            window-resize {
                spring damping-ratio=0.80 stiffness=900 epsilon=0.0001
            }
            workspace-switch {
                spring damping-ratio=0.85 stiffness=850 epsilon=0.0001
            }
            overview-open-close {
                spring damping-ratio=0.85 stiffness=800 epsilon=0.0001
            }
            screenshot-ui-open {
                duration-ms 200
                curve "ease-out-expo"
            }
            window-open {
                duration-ms 200
                curve "ease-out-expo"
            }
            window-close {
                duration-ms 150
                curve "ease-out-quad"
            }
        }

        // Noctalia surfaces blur what is behind them, not the wallpaper alone.
        layer-rule {
            match namespace="^noctalia-(bar|notification|dock|panel|attached-panel|osd).*"
            background-effect {
                xray false
            }
        }

        layer-rule {
            match namespace="^noctalia-backdrop.*"
            background-effect {
                blur false
            }
        }

        // Screenshot selection and annotation overlays stay sharp.
        layer-rule {
            match namespace="^noctalia-(screenshot-region|annotate).*"
            background-effect {
                blur false
                xray false
            }
        }

        // Rounded corners for every window, matching the bar capsules.
        window-rule {
            geometry-corner-radius 16
            clip-to-geometry true
            draw-border-with-background false
        }

        // kitty is translucent (modules/home/kitty.nix); blur what is behind it.
        window-rule {
            match app-id="^kitty$"
            background-effect {
                blur true
                xray false
            }
        }

        binds {
            Mod+Slash hotkey-overlay-title="Shell: Show keybind cheatsheet" { show-hotkey-overlay; }

            Mod+Return hotkey-overlay-title="Applications: Open terminal" { spawn "kitty"; }
            Mod+Q hotkey-overlay-title="Windows: Close active window" { close-window; }
            Mod+L hotkey-overlay-title="Session: Lock screen" { spawn "noctalia" "msg" "session" "lock"; }

            Mod+Left { focus-column-left; }
            Mod+Right { focus-column-right; }
            Mod+Up { focus-window-up; }
            Mod+Down { focus-window-down; }
            Mod+H { focus-column-left; }
            Mod+J { focus-window-down; }
            Mod+K { focus-window-up; }

            Mod+Shift+Left { move-column-left; }
            Mod+Shift+Right { move-column-right; }
            Mod+Shift+Up { move-window-up; }
            Mod+Shift+Down { move-window-down; }
            Mod+Shift+H { move-column-left; }
            Mod+Shift+J { move-window-down; }
            Mod+Shift+K { move-window-up; }

            Mod+1 { focus-workspace 1; }
            Mod+2 { focus-workspace 2; }
            Mod+3 { focus-workspace 3; }
            Mod+4 { focus-workspace 4; }
            Mod+5 { focus-workspace 5; }
            Mod+6 { focus-workspace 6; }
            Mod+7 { focus-workspace 7; }
            Mod+8 { focus-workspace 8; }
            Mod+9 { focus-workspace 9; }

            Mod+Shift+1 { move-column-to-workspace 1; }
            Mod+Shift+2 { move-column-to-workspace 2; }
            Mod+Shift+3 { move-column-to-workspace 3; }
            Mod+Shift+4 { move-column-to-workspace 4; }
            Mod+Shift+5 { move-column-to-workspace 5; }
            Mod+Shift+6 { move-column-to-workspace 6; }
            Mod+Shift+7 { move-column-to-workspace 7; }
            Mod+Shift+8 { move-column-to-workspace 8; }
            Mod+Shift+9 { move-column-to-workspace 9; }

            Mod+BracketLeft { consume-or-expel-window-left; }
            Mod+BracketRight { consume-or-expel-window-right; }
            Mod+Comma { consume-window-into-column; }
            Mod+Period { expel-window-from-column; }
            Mod+R { switch-preset-column-width; }
            Mod+F { maximize-column; }
            Mod+Shift+F { fullscreen-window; }
            Mod+Minus { set-column-width "-10%"; }
            Mod+Equal { set-column-width "+10%"; }
            Mod+Tab hotkey-overlay-title="Shell: Toggle workspace overview" { toggle-overview; }

            Mod+WheelScrollDown { focus-column-right; }
            Mod+WheelScrollUp { focus-column-left; }
            Mod+Shift+WheelScrollDown { move-column-right; }
            Mod+Shift+WheelScrollUp { move-column-left; }

            // Noctalia shell verbs; `noctalia` is on PATH via programs.noctalia
            // (modules/home/noctalia.nix).
            Mod+Space hotkey-overlay-title="Shell: Toggle application launcher" { spawn "noctalia" "msg" "panel-toggle" "launcher"; }
            Mod+S hotkey-overlay-title="Shell: Toggle settings" { spawn "noctalia" "msg" "settings-toggle"; }
            Mod+C hotkey-overlay-title="Shell: Toggle clipboard history" { spawn "noctalia" "msg" "panel-toggle" "clipboard"; }
            Mod+W hotkey-overlay-title="Shell: Choose wallpaper" { spawn "noctalia" "msg" "panel-toggle" "wallpaper"; }
            Mod+Shift+E hotkey-overlay-title="Shell: Toggle session menu" { spawn "noctalia" "msg" "panel-toggle" "session"; }
            Mod+N hotkey-overlay-title="Shell: Toggle control center" { spawn "noctalia" "msg" "panel-toggle" "control-center"; }
            Mod+D hotkey-overlay-title="Utilities: Toggle settings (display config)" { spawn "noctalia" "msg" "settings-toggle"; }

            // Media and brightness keys, usable while locked. Volume keeps the
            // explicit 5-unit step; brightness omits the argument because
            // Noctalia's first positional there is <target>, so its configured
            // step applies.
            XF86AudioRaiseVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-up" "5"; }
            XF86AudioLowerVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-down" "5"; }
            XF86MonBrightnessUp allow-when-locked=true { spawn "noctalia" "msg" "brightness-up"; }
            XF86MonBrightnessDown allow-when-locked=true { spawn "noctalia" "msg" "brightness-down"; }
            XF86AudioMute allow-when-locked=true repeat=false { spawn "noctalia" "msg" "volume-mute"; }
            XF86AudioMicMute allow-when-locked=true repeat=false { spawn "noctalia" "msg" "mic-mute"; }
            XF86AudioPlay allow-when-locked=true repeat=false { spawn "noctalia" "msg" "media" "toggle"; }
            XF86AudioNext allow-when-locked=true repeat=false { spawn "noctalia" "msg" "media" "next"; }
            XF86AudioPrev allow-when-locked=true repeat=false { spawn "noctalia" "msg" "media" "previous"; }
        }
      '';
    };
  };
}
