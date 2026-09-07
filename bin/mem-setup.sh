#!/bin/sh
# Eleva o limite de memória que o macOS permite à GPU (padrão: ~75% da RAM = 36 GB).
# Necessário para a config A (~33 GB de pesos + KV cache + scratch de prefill).
#
# ATENÇÃO: NÃO persiste entre reboots — rodar de novo após reiniciar a máquina.
# Isso é intencional: um limite persistente + modelo mal dimensionado = boot loop.
#
# Uso: sudo bin/mem-setup.sh

set -eu

TARGET_MB=40960

current=$(sysctl -n iogpu.wired_limit_mb)
echo "iogpu.wired_limit_mb atual: ${current} (0 = padrão do sistema, ~36 GB nesta máquina)"

sysctl "iogpu.wired_limit_mb=${TARGET_MB}"
echo "OK: limite da GPU elevado para ${TARGET_MB} MB (40 GB). Válido até o próximo reboot."
