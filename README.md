# Zabbix host auto classifier

A Bash script that automatically assigns every Zabbix host to the correct host
groups based on its host name, using the JSON-RPC API.

## What it does

It fetches all hosts and applies two kinds of grouping to each one:

- **Role group**, derived from a substring of the name (for example `*DCV*`
  becomes a Domain Controller, `*VTP*` a virtualization host, `*DBV*` a
  database server).
- **Site group**, derived from the leading site code of the name.

Groups are created on demand if they do not exist. The classification rules are
just string matches, so they adapt to any consistent host naming scheme.

## When to use it

When your hosts follow a naming convention and you want them grouped by role
and by site automatically, instead of tagging each one by hand, or to re-sort
everything after a bulk import.

## Configuration

Editable at the top of the script:

- `ZABBIX_URL`, `ZABBIX_HOST_HEADER`, `ZABBIX_USER`, `ZABBIX_PASS`
- `SITE_GROUPS` : site code to group name
- the naming substrings in the classification block (adapt them to your scheme)

## Usage

```bash
./zabbix_classify_hosts.sh
```

> Site names and the naming substrings are placeholders / example specific.
> Adjust them to match your environment.
