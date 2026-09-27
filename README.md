<div align="center">

# 🔵 voidbr-snapper-manager

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

O openSUSE resolve isso com um layout e um GRUB próprios. As outras distros com o layout flat trocam o `@` pelo snapshot, com ferramentas como `snapper-rollback` (Arch) e Timeshift (Mint/Ubuntu). O `voidbr-snapper-manager` faz essa troca no VoidBR e soma a ela os snapshots automáticos do xbps.

---

## Requisitos

| Item | Detalhe |
|---|---|
| Sistema de arquivos | `/` em **btrfs** |
| Layout | `@` (raiz), `@snapshots` (montado em `/.snapshots`) e, opcional, `@home` |
| snapper | com a config `root` para o `/` |
| voidbr-xbps | xbps com suporte a hooks (`/etc/xbps.d/hooks.d/*.hook`) |
| Bootloader | GRUB com **grub-btrfs**, para bootar em snapshots pelo menu |
| Agendador | **cronie**, que roda o `/etc/cron.hourly/snapper` (snapshots periódicos **e a limpeza automática**) |
| Notificação (opcional) | `libnotify` (`notify-send`) |

Sem `voidbr-xbps` os hooks não rodam, mas `list`, `diff` e `restore` continuam funcionando.

---

## Instalação

```sh
sudo xbps-install -S voidbr-snapper-manager
```

### Sistema instalado sem subvolumes

Se o `/` estiver direto na raiz do btrfs (sem `@`), converta antes para o layout suportado:

```sh
sudo voidbr-snapper-manager migrate
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
sudo voidbr-snapper-manager migrate finish   # apaga o sistema antigo da raiz
```

> Tire um backup antes. Por enquanto o `migrate` suporta só GRUB (UEFI, UEFI `--removable` e BIOS).

### Configuração

Depois, configure uma vez:

```sh
sudo voidbr-snapper-manager setup
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
exec-once = voidbr-snapper-manager check --notify
```

---

## Como funciona

### Snapshots automáticos

A cada transação do xbps:

```
xbps-install -Su
  ├─ 00-voidbr-snapper-pre.hook   →  snapshot "pre"   (antes de tudo)
  ├─ ... instala / atualiza / remove ...
  └─ 99-voidbr-snapper-post.hook  →  snapshot "post"  (depois de todos os hooks)
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
voidbr-snapper-manager list               lista os snapshots
voidbr-snapper-manager diff [N]           o que mudou na transação do pre N (padrão: a última)
sudo voidbr-snapper-manager restore [N]   restaura o sistema para o snapshot N
voidbr-snapper-manager check [--notify]   avisa se o sistema foi iniciado num snapshot
sudo voidbr-snapper-manager setup         cria a config do snapper e libera o grupo wheel
sudo voidbr-snapper-manager migrate       converte o / da raiz do btrfs para @/@home/@snapshots
sudo voidbr-snapper-manager migrate finish   depois do reboot, apaga o sistema antigo
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
   sudo voidbr-snapper-manager restore
   ```
3. Reinicie e escolha a entrada **normal** do sistema.

### Ver o que uma atualização mudou

```sh
voidbr-snapper-manager diff        # última transação
voidbr-snapper-manager diff 42     # transação do pre 42
```

### Interface gráfica

```sh
voidbr-snapper-manager-gui
```

Ou pelo menu, em **VoidBR Snapper Manager**. A janela mostra os snapshots (com os pares antes/depois e os importantes marcados), as alterações de cada atualização, o estado do sistema no rodapé e um aviso quando o sistema foi iniciado a partir de um snapshot, com o botão para restaurá-lo.

As ações (criar, apagar, restaurar, configurar) pedem a senha pelo polkit. No Hyprland é preciso ter um agente polkit rodando (por exemplo, `hyprpolkitagent`).

### Limine

O Limine não lê btrfs: o kernel e o initramfs precisam estar na ESP. O `update-limine` do VoidBR:

- adiciona `rootflags=subvol=@` nas entradas do sistema;
- chama `voidbr-snapper-manager limine-entries`, que gera o submenu **Snapshots do sistema** no `limine.conf`, com uma entrada por snapshot (`rootflags=subvol=@snapshots/N/snapshot`).

Cada snapshot usa o kernel que estava instalado nele. Se for a mesma versão que já está na ESP, os arquivos são reaproveitados. Se não, o kernel/initramfs do snapshot é copiado para `/boot/efi/limine/snapshots/` (deduplicado por hash), desde que caiba, e os kernels do sistema sempre têm prioridade no espaço. O menu é refeito a cada snapshot criado ou apagado.

No `restore` com Limine, os kernels da ESP são recopiados a partir do `@` restaurado. Se o snapshot tiver outro kernel, o restore exige que o sistema tenha sido iniciado nele pelo menu de boot.

### Agendamento (snapshots periódicos)

Além dos snapshots de cada atualização, o snapper pode guardar snapshots periódicos (o "timeline"). Quem executa é o `/etc/cron.hourly/snapper`, rodado pelo **cronie**. O mesmo cron faz a **limpeza automática** de todos os snapshots (`NUMBER_LIMIT`, limites do timeline e pares pre/post vazios): **sem o cronie ativo, nenhum snapshot é apagado**.

O `setup` ativa o cronie e, na primeira vez, aplica o padrão do VoidBR: **1 snapshot por dia, guardando 7**. Para mudar:

```sh
voidbr-snapper-manager schedule                 # mostra o agendamento atual
sudo voidbr-snapper-manager schedule daily 7    # 7 diários
sudo voidbr-snapper-manager schedule daily 7 weekly 4
sudo voidbr-snapper-manager schedule off        # só os snapshots das atualizações
```

Períodos: `hourly`, `daily`, `weekly`, `monthly`, `yearly`. Com `off`, a limpeza automática continua funcionando. Na interface gráfica: menu ☰ → **⏰ Agendamento**.

Com o Limine, o menu de snapshots é refeito uma vez por dia pelo `/etc/cron.daily/voidbr-snapper-manager`, e não a cada snapshot do timeline, para não reescrever a ESP de hora em hora.

### Pular o snapshot numa transação

```sh
sudo VOIDBR_SNAPPER_SKIP=1 xbps-install -S pacote
```

---

## Configuração

`/etc/voidbr-snapper-manager.conf`

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
| `/usr/bin/voidbr-snapper-manager` | script |
| `/etc/voidbr-snapper-manager.conf` | configuração |
| `/etc/xbps.d/hooks.d/00-voidbr-snapper-pre.hook` | hook do snapshot pre |
| `/etc/xbps.d/hooks.d/99-voidbr-snapper-post.hook` | hook do snapshot post |
| `/etc/xdg/autostart/voidbr-snapper-manager.desktop` | notificação ao logar |
| `/etc/bash/bashrc.d/voidbr-snapper-manager.sh` | aviso ao abrir o terminal |
| `/etc/cron.daily/voidbr-snapper-manager` | atualiza o menu do Limine uma vez por dia |
| `/run/voidbr-snapper-manager/pre` | número do pre da transação em andamento |

---

## Limitações

- **Limine e espaço na ESP:** o Limine só lê a ESP (FAT). Snapshots com o mesmo kernel do sistema reaproveitam os arquivos que já estão lá, sem custo. Snapshots com um kernel que não existe mais precisam de cópia própria e só entram no menu se couberem na ESP. Com ESP pequena (128 MB), na prática só entram os snapshots com o kernel atual.
- **`/home`** não volta no tempo. Só o sistema (`@`) é restaurado.
- Com o `/var/log` dentro do `@`, os logs também voltam junto com o snapshot.
- Não use `snapper rollback` nesse layout, porque ele não tem efeito. Use `voidbr-snapper-manager restore`.

---
