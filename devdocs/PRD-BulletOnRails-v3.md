# Product Requirement Document (PRD) - Bullet on Rails
**Autor:** Carllos / Michael D. Bullet  
**Versão:** 3.0  
**Data:** 27/09/2026  
**Status:** Pronto para Implementação  

---

## 1. Visão Geral do Produto
O **Bullet on Rails** é uma plataforma de streaming sob demanda (VOD) de alta performance voltada para filmes, séries e conteúdos digitais exclusivos. O foco estratégico do projeto é entregar uma experiência de usuário idêntica à da Netflix (rápida, fluida e intuitiva), mantendo o **custo de infraestrutura no menor patamar possível** através do desacoplamento de mídia e aplicando mecanismos rigorosos contra a pirataria e o download ilegal de conteúdo.

---

## 2. Arquitetura de Infraestrutura e Custos (Foco em Economia)
A infraestrutura centralizada utilizará o **Bunny.net** (Bunny Stream) como pilar único de armazenamento, transcoding e entrega de vídeo de borda, eliminando custos de processamento de servidores VPS tradicionais.

```
[Painel Admin / Upload via Tus] -> [Bunny Stream API] -> [Transcoding Automático (HLS)]
                                                                  |
[Usuário / Aluno] <------- [Site / App Client (play)] <----- [Bunny CDN (Entrega Segura)]
```

### Componentes de Infraestrutura:
1. **Armazenamento e Transcoding (Bunny Stream):** 
   - Armazenamento em nuvem otimizado para vídeos a $0.01/GB.
   - Codificação automática para múltiplos formatos e resoluções dinâmicas (Adaptive Bitrate Streaming via HLS - 360p, 480p, 720p, 1080p).
2. **Distribuição Global (Bunny CDN):**
   - Entrega de dados via rede de borda (Edge) de baixa latência a partir de $0.005/GB.
3. **Servidor da Aplicação (Backend/Frontend):**
   - Hospedagem da aplicação em VPS leve (ex: Hetzner / DigitalOcean) ou arquitetura Serverless (Vercel / Cloudflare Pages). O servidor **não processa nem distribui os vídeos**, gerenciando apenas dados textuais, progresso e autenticação.

---

## 3. Requisitos Funcionais (Funcionalidades Principais)

### 3.1. Experiência de Streaming (Interface "Netflix Style")
* **RF01 - Player Customizado:** O player de vídeo (injetado via SDK/Iframe do Bunny ou bibliotecas como Video.js/Hls.js) deve ocultar completamente a URL de origem física do arquivo de mídia.
* **RF02 - Resolução Dinâmica (ABR):** Ajuste automático e transparente da qualidade do vídeo com base na estabilidade e velocidade da internet do usuário.
* **RF03 - Memorização de Progresso:** O sistema deve salvar no banco de dados o segundo exato onde o usuário interrompeu o vídeo e sincronizar em tempo real entre dispositivos.
* **RF04 - Autoplay e Avanço Automático:** O próximo episódio ou filme sequencial deve iniciar automaticamente após o término da mídia atual.

### 3.2. Gerenciamento e Segurança Antipirataria
* **RF05 - Restrição de Domínio (Domain Lock):** Os vídeos hospedados na biblioteca do Bunny Stream só podem ser reproduzidos se a requisição originar-se estritamente do domínio principal `bulletonrails.com` ou do subdomínio do aplicativo `play.bulletonrails.com`. Acessos diretos ou por iFrames externos serão bloqueados nativamente com Erro 403.
* **RF06 - Marca D'água Dinâmica (Watermarking):** O e-mail e o CPF do usuário autenticado devem ser renderizados de forma flutuante, semitransparente e em intervalos/posições aleatórias sobre a tela do vídeo. A camada deve ser estruturada em HTML/CSS acima do player utilizando a propriedade `pointer-events: none` para impedir inspeção simples e bloqueio por adblockers.
* **RF07 - Bloqueio de Acessos Simultâneos:** Impedir sessões simultâneas ativas assistindo a mídias diferentes sob a mesma conta em localizações geográficas distintas.

### 3.3. Painel Administrativo (Upload de Arquivos)
* **RF08 - Upload Resiliente em Lote:** O administrador realiza o envio de arquivos brutos (.mp4, .mkv) diretamente através do painel administrativo. O envio deve utilizar obrigatoriamente fragmentação de dados (**Tus Protocol / Chunk Upload**) conectado à API do Bunny Stream, permitindo pausar e retomar uploads grandes sem perda de progresso.

---

## 4. Requisitos Não-Funcionais (Qualidade e Performance)
* **RNF01 - Latência de Reprodução:** O tempo de resposta para o início do vídeo (Time-to-First-Frame) não deve ultrapassar 1.5 segundos em conexões estáveis de banda larga ou 4G, devido à fragmentação HLS (.m3u8).
* **RNF02 - Segurança de Endpoints (Signed URLs):** O backend deve gerar tokens criptografados de curta duração (Signed Tokens) anexados à URL do manifesto do Bunny. O link expira em minutos, impedindo a extração estável da URL por ferramentas de inspeção do navegador (F12).
* **RNF03 - Escalabilidade de Banda:** A camada de entrega delegada à CDN do Bunny deve suportar picos de até 10.000 usuários simultâneos sem degradação na taxa de transferência de bits.

---

## 5. Modelo de Dados Simplificado
* **Usuários:** `ID`, `Nome`, `Email`, `CPF`, `Status_Assinatura`, `Created_At`.
* **Mídias (Filmes/Séries):** `ID`, `Título`, `Descrição`, `Tipo (Filme/Episódio)`, `Série_ID (Opcional)`, `Temporada (Opcional)`, `Thumbnail_URL`.
* **Configurações_Bunny:** `ID`, `Mídia_ID`, `Bunny_Video_ID`, `Duração_Segundos`.
* **Progresso_Video:** `ID`, `Usuario_ID`, `Mídia_ID`, `Tempo_Segundos`, `Concluído (Booleano)`, `Updated_At`.

---

## 6. Próximos Passos e Roadmap de Implementação
1. **Fase 1 (Infra):** Criação da conta no Bunny.net, configuração da Stream Library e ativação do Token Authentication global.
2. **Fase 2 (Backend):** Estruturação das tabelas de progresso e desenvolvimento do script gerador de URLs Assinadas (SHA256).
3. **Fase 3 (Frontend):** Desenvolvimento da interface de catálogo e acoplamento do player com tratamento de camada anti-F12 (Watermark).