# DKB PC Recomp — Otimização (fork matheus-rocha0/dkb-pc-recomp)

## Contexto e Travas de Segurança
- **Fork Oficial de Trabalho (`origin`):** `https://github.com/matheus-rocha0/dkb-pc-recomp.git` (clone em `C:\Users\Matheus_\dev\dkb-pc-recomp`)
- **Proteção contra Push Indevido:** Remotes `upstream` (`Lucas-blip-png/dkb-pc-recomp`) e `totk` (`valentderah/totk-pc-recomp`) travados com push URL `NO_PUSH_*`. É fisicamente impossível dar push para o repositório original de terceiros.
- **Versão Estável Preservada:**
  - Tag `stable-installed-0.1.0` e branch `stable-installed` criadas no commit exato do executável instalado (`9837982`) e enviadas (`git push`) para o fork `origin`.
  - Backup físico completo de `dkb.exe`, `dkb.ini`, DLLs e caches em `C:\Users\Matheus_\OpenBot\Agents\agent-db4e3750-7de8-40c0-bbb8-3edd489aec8f\DKB-Recomp\backup_2026-11-08\`.
- **Hardware:** Ryzen 5 5600, RTX 4060 Ti 8GB (driver 610.88), 32 GB RAM, NVMe.
- **Orquestração:** Tech Lead (terminal "Shell" no Maestri) + 5 workers Maestri em paralelo (`Gemini 3.8 Flash - High`).

## Fase 1 — Análise (2026-11-08) ✅
- DKB congelou o runtime no TotK v0.2.8 (merge-base `f469c5a`); TotK tem +470 commits (`v0.3.13`) com otimizações críticas. → `scratch/report_divergence.md`
- Logs: DKB 1% low 20–34 FPS, freezes de até 4 s. Causas: `replay_async=1` (8,7 s de esperas `guest_read`), `shader-cache` não empacotado (80.634 arquivos soltos), `pipeline-keys` pequeno (424 vs 5.612 prewarm), tradução de shader em runtime. → `scratch/report_runtime.md`

## Fase 2 — Execução em Paralelo no Maestri ✅
| Worker (Canvas) | Worktree / Alvo | Escopo | Status |
|---|---|---|---|
| **Selo** | `installed_game` | Backup completo + `replay_async=0` no `dkb.ini` + empacotamento `shader-cache.pack` | Concluído com sucesso (113.107 shaders no .pack, relatório em `scratch/quickwins_selo.md`) |
| **Pulso** | `dkb-wt-sync` (`perf/sync`) | `task/recline`, `task/copystat`, `task/cmdbuf`, `frame_queue` | Concluído (commit `c83f0f2`, relatório em `scratch/port_pulso.md`) |
| **Cofre** | `dkb-wt-memory` (`perf/memory`) | `task/wbmerge`, `task/poolfree`, `task/deferstamp`, `task/gpuswz`, `task/vrampress` | Concluído (commit `cb098b8`, relatório em `scratch/port_cofre.md`) |
| **Rastreador** (Traço) | `dkb-wt-draw` (`perf/draw`) & `dkb-wt-memory` (`perf/memory`) | `task/perfdraw`, `task/dynstate` em `perf/draw` (commit `589eabd`); `runtime/vk_texture.c` em `perf/memory` (`task/gpuswz`, `task/poolfree`, `task/vrampress`, `1c5c6fd`, preservando NVN 2 / `TEX_HASH`) | Concluído (commit `589eabd` e `cb098b8`, relatório em `scratch/port_tex_rastreador.md`) |
| **Forja** (Sonda) | `dkb-pc-recomp` (`tools/local_build.ps1`) | Script de build reproduzível com toolchain portátil + cache incremental + build baseline concluído com sucesso (507,8 s inicial, 1,5 s rebuild) | Concluído (`scratch/build_forja.md`) |

## Fase 3 — Integração, Build Otimizado e Validação ✅
- **Integração das Branches:** Unificação das 3 branches de performance (`perf/sync`, `perf/draw`, `perf/memory`) sobre `perf/integration` com resolução exata de conflitos em `runtime/cfg.c` preservando 100% das chaves.
- **Shader Headers:** Validados com `tools/build_shaders.py --check` (código 0).
- **Compilação Otimizada:** Executável gerado com sucesso via [`tools/local_build.ps1`](tools/local_build.ps1) em `C:\Users\Matheus_\dev\dkb-build\optimized\dkb.exe` (190.310.912 bytes, 181.49 MB, link em 1,0 s).
- **Self-Tests e Probes de Subsistemas:**
  - `--version`: `dkb 0.1.0+76c76f5 (Donkey Kong Bananza 1.0.0)`
  - `--selftest`: 180.061 funções roteadas no dispatch, heap e virtual memory OK (0 failures).
  - `--probe-cfg`: Parsing e validação de chaves do .ini OK (`probe-cfg: ok`).
  - `--probe-dpi`: Manifest v2 e dimensões de monitor OK.
  - `--probe-kernel`: Escalonador preemptivo, condvars, 33 threads e 5059 SVCs OK.
  - `--probe-ipc`: Comunicação TIPC/CMIF com audren OK.
  - `--probe-fs`: Montagem de RomFS e transações de save OK (75.238 arquivos verificados).
  - `--probe-gfx-abi`: Layouts de estruturas e NVNtextureView OK (28 layouts ajustados).
  - `--probe-astc`: Decodificador computacional ASTC testado em 14 footprints, bit-exact com astc_decode_ldr (0 erros).
  - `--probe-vkmem` (com `TOTK_DESWIZZLE=check`): `passed` (343 casos de deswizzle CPU, 186.758 blocos ASTC, 130 formatos mapeados, 41 GPU checks incluindo validação bit-a-bit do compute shader `bl_deswizzle.comp` no layout Switch 2 GOB contra a referência CPU, 0 validation errors).
- **Sincronização com Fork:** `bananza` atualizada via fast-forward com `perf/integration` e enviada para `origin`.
- **Ambiente de Teste Seguro:** Pasta `C:\Users\Matheus_\dev\dkb-build\optimized` estruturada com junções NTFS para `romfs`, `exefs`, `shader-cache` e cópia de `dkb.ini` configurado para testes de gameplay do usuário.
