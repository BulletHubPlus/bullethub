# RIPD: Relatório de Impacto à Proteção de Dados Pessoais

**Controlador:** bullethub.app · **Versão:** rascunho 0.1 (28/09/2026) · **Status:** aguardando revisão do DPO

> Rascunho técnico preparado a partir do PRD v4 (§12) e do que o sistema de fato faz hoje. **Não é aconselhamento jurídico.** Bases legais, prazos e a decisão sobre transferência internacional precisam ser validados pelo DPO antes do lançamento.

## 1. Descrição do tratamento

Plataforma de vídeo por assinatura (filmes, séries e animes). O titular cria conta, assina um plano e assiste pelo navegador. O vídeo é servido pelo Bunny Stream (Bunny.net, com armazenamento padrão em Frankfurt); a aplicação roda em servidor próprio (Coolify) com PostgreSQL.

## 2. Dados tratados, finalidade, base legal e retenção

| Dado | Onde | Finalidade | Base legal provável (art. 7º) | Retenção | Proteção |
| --- | --- | --- | --- | --- | --- |
| Nome, e-mail | `users` | Conta, autenticação, comunicação | Execução de contrato (V) | Enquanto houver conta | E-mail mascarado na watermark (`ca***@gmail.com`) e filtrado dos logs |
| CPF | `users.cpf_encrypted`, `users.cpf_hash` | Nota fiscal; uma conta por pessoa (antifraude) | Obrigação legal/regulatória (II) e execução de contrato (V) | Enquanto houver conta + 5 anos (fiscal) | Cifrado em repouso (AES-256-GCM); unicidade por HMAC com chave separada; exibido só mascarado (`529.***.***-25`); nunca na watermark |
| Senha | `users.password_hash` | Autenticação | Execução de contrato (V) | Enquanto houver conta | Argon2id; nunca armazenada em claro |
| Dispositivos (nome, user agent) | `devices` | Gerenciar sessões, revogar acesso | Execução de contrato (V) | Enquanto houver conta | Apagados na exclusão |
| IP e user agent de reprodução | `playback_sessions` | Limite de telas, antipirataria | Legítimo interesse (IX) | **30 dias** (expurgo diário) | Após 30 dias o IP é apagado; o código da sessão permanece para rastrear vazamentos |
| Eventos de segurança (IP, UA) | `security_events` | Detectar abuso: login falho, reuso de token, marca d'água adulterada | Legítimo interesse (IX) | **90 dias** (expurgo diário) | Acesso restrito a owner/suporte |
| Progresso de reprodução | `watch_progress` | Continuar assistindo | Execução de contrato (V) | Enquanto houver conta | Apagado na exclusão |
| Assinatura | `subscriptions` | Cobrança e acesso | Execução de contrato (V); obrigação legal (II) | Enquanto houver conta + 5 anos (fiscal) | Mantida e cancelada na exclusão |
| Telemetria de qualidade (tempo até o 1º frame, travamentos) | só métricas agregadas | Melhoria do serviço | Legítimo interesse (IX) | Agregada; sem armazenamento por evento | **Sem identificação:** nem usuário nem sessão |

> **Legítimo interesse:** para os dois casos de IX (IP de reprodução e eventos de segurança), o DPO precisa registrar o teste de balanceamento (LIA).

## 3. Direitos do titular (art. 18): como são atendidos

| Direito | Implementação | Prazo |
| --- | --- | --- |
| Confirmação e acesso | "Minha conta" mostra os dados; `GET /api/me` | Imediato |
| Portabilidade | "Baixar meus dados" → JSON com todas as categorias acima (`Accounts.export_user_data/1`) | Imediato (a lei pede até 15 dias) |
| Eliminação | "Excluir conta", com confirmação de senha (`Accounts.erase_user/1`) | Imediato |
| Correção | Nome e senha pelo próprio titular; demais dados via suporte | até 15 dias |
| Revogação / oposição | Suporte (canal a definir: e-mail do DPO) | até 15 dias |

**O que a exclusão faz:**
- **Apaga:** nome, e-mail, senha, dispositivos, tokens e progresso.
- **Desvincula:** as sessões de reprodução e os eventos de segurança deixam de apontar para a pessoa, e os IPs são apagados.
- **Mantém pelo prazo fiscal:** CPF cifrado e assinaturas, que são canceladas.
- **Efeito colateral:** o CPF retido continua impedindo um novo cadastro com o mesmo CPF (antifraude). **O DPO deve confirmar se isso é aceitável.**

## 4. Compartilhamento e transferência internacional

- **Bunny.net (vídeo):** nenhum dado pessoal do assinante é enviado. O token de reprodução é uma assinatura opaca (SHA-256) sobre o id do vídeo e a expiração; o e-mail e o código da sessão são desenhados na tela pelo navegador, sobre o player, e não vão para o Bunny. **Conclusão preliminar:** não há transferência internacional de dados pessoais por meio do Bunny.
- **Resend (e-mail transacional):** recebe nome e e-mail para enviar confirmações e redefinições de senha. **Há transferência internacional (EUA).** O DPO precisa definir o mecanismo (art. 33: cláusulas contratuais padrão ou consentimento específico).
- **Gateway de pagamento:** ainda não definido (Fase 3). Precisa entrar neste RIPD antes do lançamento.
- **Sentry / Grafana Cloud (Fase 4):** configurar sem PII (sem e-mail, CPF ou IP) antes de ativar.

## 5. Riscos e medidas

| Risco | Probabilidade | Impacto | Medida adotada |
| --- | --- | --- | --- |
| Vazamento do banco expõe CPF | Baixa | Alto | CPF cifrado; chave (`CLOAK_KEY`) fora do banco, só em variável de ambiente; backup da chave separado |
| Frame de vídeo vazado expõe dado do assinante | Alta | Médio | Watermark só com e-mail mascarado e código opaco; nunca CPF |
| Roubo de sessão | Média | Médio | Access token de 15 min só em memória; refresh em cookie HttpOnly/SameSite=Strict; reuso detectado revoga o dispositivo |
| Logs com dados pessoais | Média | Médio | `filter_parameters` (senha, CPF, e-mail, tokens); logs só com `user_id` |
| Retenção excessiva | Média | Baixo | Expurgo diário automático (`PurgeExpiredData`) |
| Acesso indevido por funcionário | Baixa | Alto | Papéis (owner, editor, suporte); o editor não acessa contas; suspensões auditadas em `security_events` |

## 6. Pendências para aprovação

- [ ] DPO nomeado e canal do titular publicado (e-mail).
- [ ] Validar as bases legais e os prazos da tabela 2.
- [ ] LIA para os tratamentos por legítimo interesse.
- [ ] Mecanismo de transferência internacional para o Resend (e para o gateway, quando for escolhido).
- [ ] Decidir se o CPF retido deve continuar bloqueando um novo cadastro após a exclusão.
- [ ] Política de privacidade e termos de uso publicados no site.
- [ ] Incluir o gateway de pagamento quando ele for definido.
