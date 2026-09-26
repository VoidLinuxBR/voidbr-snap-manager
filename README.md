<div align="center">

# 🔵 voidbr-snap-manager

**Snapshots btrfs+snapper automáticos no xbps (hooks pre/post) e restauração trocando o @**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

</div>

---

Snapshots automáticos do sistema a cada atualização do xbps e restauração simples de um snapshot, para o **VoidBR Linux** com **btrfs + snapper**.

- Cria um par de snapshots **pre/post** a cada `xbps-install` / `xbps-remove`, pelos hooks do `voidbr-xbps` (igual ao `snap-pac` do Arch).
- Restaura o sistema para qualquer snapshot com um comando, trocando o subvolume `@`.
- Avisa quando o sistema foi iniciado a partir de um snapshot e oferece a restauração.
- O sistema anterior vira um snapshot comum do snapper e é apagado pela limpeza automática do snapper, como no openSUSE.

---

## Por que existe

No layout btrfs mais comum (`@`, `@home`, `@snapshots`, estilo Arch Wiki), o `/` é montado pelo nome `@`, no fstab e no bootloader. O `snapper rollback` funciona marcando um snapshot como **subvolume padrão** do btrfs, mas com o `subvol=@` fixo esse padrão é ignorado e o sistema continua subindo o `@` antigo. Na prática, o rollback "funciona" e não muda nada.

O openSUSE resolve isso com um layout e um GRUB próprios. As outras distros com o layout flat trocam o `@` pelo snapshot, com ferramentas como `snapper-rollback` (Arch) e Timeshift (Mint/Ubuntu). O `voidbr-snap-manager` faz essa troca no VoidBR e soma a ela os snapshots automáticos do xbps.

---

## Requisitos

| Item | Detalhe |
|---|---|
| Sistema de arquivos | `/` em **btrfs** |
| Layout | `@` (raiz), `@snapshots` (montado em `/.snapshots`) e, opcional, `@home` |
| snapper | com a config `root` para o `/` |
| voidbr-xbps | xbps com suporte a hooks (`/etc/xbps.d/hooks.d/*.hook`) |
| Bootloader | GRUB com **grub-btrfs**, para bootar em snapshots pelo menu |
| Notificação (opcional) | `libnotify` (`notify-send`) |

Sem `voidbr-xbps` os hooks não rodam, mas `list`, `diff` e `restore` continuam funcionando.

---

## Instalação

```sh
sudo xbps-install -S voidbr-snap-manager
```

### Sistema instalado sem subvolumes

Se o `/` estiver direto na raiz do btrfs (sem `@`), converta antes para o layout suportado:

```sh
sudo voidbr-snap-manager migrate
```

O `migrate`:

- confere se dá para migrar (sem subvolumes existentes, sem swapfile ativo no btrfs, com GRUB);
- cria o `@` como snapshot da raiz, o `@snapshots` e o `@home` (se o `/home` não estiver em outra partição), movendo o `/home` com reflink, sem gastar espaço;
- ajusta o fstab **dentro do novo `@`** (o original fica em `/etc/fstab.pre-migrate`);
- reinstala o GRUB e gera o `grub.cfg` a partir do novo `@`, conferindo o `rootflags=subvol=@`;
- pede para reiniciar.

Até aqui o sistema antigo continua inteiro na raiz do btrfs. Depois do reboot, confira se o sistema subiu no `@` e termine:

```sh
findmnt -no FSROOT /                      # /@
sudo voidbr-snap-manager migrate finish   # apaga o sistema antigo da raiz
```

> Tire um backup antes. Por enquanto o `migrate` suporta só GRUB (UEFI, UEFI `--removable` e BIOS).

### Configuração

Depois, configure uma vez:

```sh
sudo voidbr-snap-manager setup
```

O `setup`:

- confere se o layout é o suportado (`/` em `@`, `@snapshots` montado em `/.snapshots` pelo fstab);
- cria a config `root` do snapper sem perder o `@snapshots` (o `create-config` cria um `.snapshots` dentro do `@`, que é apagado, e o `@snapshots` volta a ser montado no lugar);
- libera o grupo `wheel` para consultar os snapshots (`ALLOW_GROUPS=wheel`, `SYNC_ACL=yes`), para `list` e `diff` rodarem sem sudo;
- ativa o serviço do grub-btrfs e atualiza o menu do GRUB.

Pode ser rodado de novo sem problema: se a config já existir, ele só ajusta o resto.

### Hyprland

O Hyprland não lê `/etc/xdg/autostart`. Para receber a notificação ao logar, adicione ao `hyprland.conf`:

```ini
exec-once = voidbr-snap-manager check --notify
```

---

## Como funciona

### Snapshots automáticos

A cada transação do xbps:

```
xbps-install -Su
  ├─ 00-voidbr-snap-pre.hook   →  snapshot "pre"   (antes de tudo)
  ├─ ... instala / atualiza / remove ...
  └─ 99-voidbr-snap-post.hook  →  snapshot "post"  (depois de todos os hooks)
```

- A descrição do snapshot traz os pacotes da transação (`xbps: linux6.6 vim ...`).
- Transações que mexem em pacotes críticos (`linux*`, `glibc`, `xbps`, `grub*`, `limine*`...) são marcadas como `important=yes` e seguem o `NUMBER_LIMIT_IMPORTANT` do snapper, então duram mais.
- Os snapshots usam `cleanup=number` e são apagados pela limpeza normal do snapper.

### Restauração

```
antes                           depois do restore 11
@            (sistema quebrado)  @snapshots/17/snapshot  ← sistema anterior (backup)
@snapshots/11/snapshot           @                       ← cópia do snapshot 11
```

1. O `@` atual é movido para `@snapshots/N/snapshot` e registrado no snapper como "backup antes do restore". **Nada é apagado.**
2. Um novo `@` é criado a partir do snapshot escolhido.
3. O subvolume padrão volta a ser o topo (`5`), o que desfaz um `snapper rollback` rodado antes.
4. No próximo boot, o sistema sobe o novo `@`.

O backup aparece no `snapper list` e no menu do grub-btrfs, então dá para voltar para ele se precisar.

---

## Uso

```
voidbr-snap-manager list               lista os snapshots
voidbr-snap-manager diff [N]           o que mudou na transação do pre N (padrão: a última)
sudo voidbr-snap-manager restore [N]   restaura o sistema para o snapshot N
voidbr-snap-manager check [--notify]   avisa se o sistema foi iniciado num snapshot
sudo voidbr-snap-manager setup         cria a config do snapper e libera o grupo wheel
sudo voidbr-snap-manager migrate       converte o / da raiz do btrfs para @/@home/@snapshots
sudo voidbr-snap-manager migrate finish   depois do reboot, apaga o sistema antigo
```

`list` e `diff` rodam sem sudo para quem está no grupo `wheel`, depois do `setup`. Sem isso, use `sudo`.

`pre` e `post` são chamados pelos hooks e não precisam ser usados à mão.

### Uma atualização quebrou o sistema

1. Reinicie e, no GRUB, entre em **snapshots** e escolha o **pre** da atualização.
2. O sistema sobe no snapshot e avisa, pela notificação ou no terminal:
   ```
   ==> AVISO: este sistema foi iniciado a partir do snapshot 42.
   restaurar agora? [s/N]
   ```
   Ou rode direto (sem número, ele usa o snapshot em que bootou):
   ```sh
   sudo voidbr-snap-manager restore
   ```
3. Reinicie e escolha a entrada **normal** do sistema.

### Ver o que uma atualização mudou

```sh
voidbr-snap-manager diff        # última transação
voidbr-snap-manager diff 42     # transação do pre 42
```

### Pular o snapshot numa transação

```sh
sudo VOIDBR_SNAP_SKIP=1 xbps-install -S pacote
```

---

## Configuração

`/etc/voidbr-snap-manager.conf`

| Variável | Padrão | Descrição |
|---|---|---|
| `snapper_config` | `root` | config do snapper usada para o `/` |
| `root_subvol` | `@` | subvolume da raiz |
| `snap_subvol` | `@snapshots` | subvolume dos snapshots |
| `abort_on_fail` | `no` | `yes` aborta a transação do xbps se o snapshot pre falhar |
| `important_pkgs` | `linux* glibc xbps voidbr-xbps grub* limine*` | pacotes que marcam o snapshot como importante |
| `desc_max` | `120` | tamanho máximo da descrição |

Os limites de quantos snapshots manter ficam no próprio snapper, em `/etc/snapper/configs/root` (`NUMBER_LIMIT`, `NUMBER_LIMIT_IMPORTANT`).

---

## Segurança

- **Os hooks nunca travam o xbps.** No `voidbr-xbps`, um hook PreTransaction que falha aborta a transação. Por isso o `pre` sai com sucesso sempre que não consegue tirar o snapshot (sem btrfs, sem config do snapper, sistema bootado num snapshot, chroot do instalador), a menos que `abort_on_fail=yes`.
- O snapper roda com `--no-dbus`, então funciona sem o `snapperd` ou o dbus (chroot, instalação).
- Com o sistema bootado num snapshot, nenhum snapshot novo é criado.
- O `restore` pede confirmação e, se algo falhar no meio, desfaz o que já tinha feito.
- O `restore` avisa quando é rodado do sistema normal em vez de um snapshot.

---

## Arquivos

| Caminho | Descrição |
|---|---|
| `/usr/bin/voidbr-snap-manager` | script |
| `/etc/voidbr-snap-manager.conf` | configuração |
| `/etc/xbps.d/hooks.d/00-voidbr-snap-pre.hook` | hook do snapshot pre |
| `/etc/xbps.d/hooks.d/99-voidbr-snap-post.hook` | hook do snapshot post |
| `/etc/xdg/autostart/voidbr-snap-manager.desktop` | notificação ao logar |
| `/etc/bash/bashrc.d/voidbr-snap-manager.sh` | aviso ao abrir o terminal |
| `/run/voidbr-snap-manager/pre` | número do pre da transação em andamento |

---

## Limitações

- **Limine:** o restore funciona igual, mas bootar num snapshot depende de o menu do Limine listar os snapshots. Por enquanto, use o GRUB (grub-btrfs) ou um live para entrar no snapshot.
- **`/home`** não volta no tempo. Só o sistema (`@`) é restaurado.
- Com o `/var/log` dentro do `@`, os logs também voltam junto com o snapshot.
- Não use `snapper rollback` nesse layout, porque ele não tem efeito. Use `voidbr-snap-manager restore`.

---
