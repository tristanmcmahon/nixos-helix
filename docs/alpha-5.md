# Alpha 5

Alpha 5 marks the first release where Helix deliberately uses the Pi-hole
running on `infernalnexus` as its system DNS resolver.

The Pi-hole service itself is owned and deployed by `hamology` on
`192.168.1.8`. This repository owns only Helix's client-side DNS policy.

## DNS and Pi-hole integration

Helix now enables:

```nix
helix.networking.pihole = {
  enable = true;
  address = "192.168.1.8";
};
```

When enabled:

- NetworkManager still manages DHCP addresses and routes.
- DHCP-provided DNS is ignored so Helix cannot silently bypass Pi-hole.
- `192.168.1.8` is Helix's sole system resolver.
- No public fallback resolver is configured during this qualification period.
- Router and LAN-wide DNS settings are unchanged; this affects Helix only.

If the Pi-hole is unavailable, DNS on Helix fails visibly rather than falling
back around the filter. Set `helix.networking.pihole.enable = false` and rebuild
to return Helix to normal NetworkManager/DHCP-provided DNS.

The Pi-hole deployment on `infernalnexus` has passed hamology's infrastructure
acceptance checks and direct DNS queries from Helix have succeeded. Alpha 5
therefore makes the integration part of Helix's declarative system state rather
than a manual resolver edit.

## Validation

After activating Alpha 5:

```bash
cat /etc/resolv.conf
dig example.com
dig openai.com
dig doubleclick.net
```

The `SERVER` line from `dig` should show:

```text
192.168.1.8#53
```

Queries should also appear in Pi-hole's Query Log.

Release tag:

```text
v0.3.0-alpha.5
```
