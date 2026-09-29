# Product Requirement Document (PRD) - BulletFlix
**Autor:** Carllos / Michael D. Bullet  
**Versão:** 1.0  
**Data:** 25/09/2026  
**Status:** Em Definição  

---

## 1. Visão Geral do Produto
O **BulletFlix** é uma plataforma de streaming sob demanda (VOD) de alta performance voltada para cursos online e conteúdos digitais exclusivos. O foco estratégico do projeto é entregar uma experiência de usuário idêntica à da Netflix (rápida, fluida e intuitiva), mantendo o **custo de infraestrutura no menor patamar possível** e aplicando mecanismos rigorosos contra a pirataria e o download ilegal de conteúdo.

---

## 2. Arquitetura de Infraestrutura e Custos (Foco em Economia)
Para evitar os custos astronômicos de servidores VPS tradicionais e a complexidade de CDN própria, a infraestrutura centralizada do BulletFlix utilizará o **Bunny.net** como pilar de armazenamento e entrega.

```
[Painel Admin / Upload] -> [Bunny Stream API] -> [Transcoding Automático (HLS)]
                                                         |
[Usuário / Aluno] <------- [Site / App Client] <----- [Bunny CDN (Entrega Segura)]
```

### Componentes de Infraestrutura:
1. **Armazenamento e Transcoding (Bunny Stream):** 
   - Armazenamento em nuvem otimizado para vídeos a $0.01/GB.
   - Codificação automática para múltiplos formatos e resoluções dinâmicas (Adaptive Bitrate Streaming - 360p, 480p, 720p, 1080p).
2. **Distribuição Global (Bunny CDN):**
   - Entrega de dados via rede de borda de baixa latência a partir de $0.005/GB.
3. **Servidor da Aplicação (Backend/Frontend):**
   - Hospedagem do site em uma VPS leve (ex: Hetzner ou DigitalOcean de $5-$10/mês) ou arquitetura Serverless (Vercel/Cloudflare Pages), já que o servidor **não processará os vídeos**, apenas os dados de usuários e progresso.

---

## 3. Requisitos Funcionais (Funcionalidades Principais)

### 3.1. Experiência de Streaming (Interface "Netflix Style")
* **RF01 - Player Customizado:** O player de vídeo deve ocultar completamente a URL de origem do arquivo de mídia.
* **RF02 - Resolução Dinâmica:** Ajuste automático da qualidade do vídeo com base na velocidade da internet do aluno.
* **RF03 - Memorização de Progresso:** O sistema deve salvar o segundo exato onde o usuário parou o vídeo e sincronizar entre dispositivos.
* **RF04 - Autoplay e Avanço Automático:** Próxima aula inicia automaticamente após o término da atual.

### 3.2. Gerenciamento e Segurança Antipirataria
* **RF05 - Restrição de Domínio (Domain Lock):** Os vídeos hospedados no Bunny só podem ser reproduzidos se a requisição vier explicitamente do domínio `bulletflix.com.br`. Se o link for copiado e aberto em outra aba ou site, o acesso será bloqueado.
* **RF06 - Marca D'água Dinâmica (Watermarking):** O e-mail e o CPF do aluno logado devem aparecer de forma flutuante e semitransparente na tela em intervalos aleatórios durante a reprodução do vídeo para coibir gravações de tela.
* **RF07 - Bloqueio de Acessos Simultâneos:** Impedir que uma mesma conta assista a dois vídeos simultaneamente em localizações geográficas diferentes.

### 3.3. Painel Administrativo (Upload de Arquivos)
* **RF08 - Upload Direto via Painel:** O administrador faz o upload do arquivo bruto (.mp4, .mkv) direto pelo painel administrativo da BulletFlix, enviando os dados em lote (chunk upload) diretamente para a API do Bunny Stream.

---

## 4. Requisitos Não-Funcionais (Qualidade e Performance)
* **RNF01 - Latência de Reprodução:** O tempo de resposta para dar "Play" em um vídeo não deve ultrapassar 1.5 segundos em conexões 4G/Banda Larga estáveis.
* **RNF02 - Segurança de Endpoint:** Tokens de reprodução assinados por tempo limitado (Signed URLs) gerados via backend para mitigar extração de links por ferramentas de inspeção de código (F12).
* **RNF03 - Escalabilidade de Banda:** A camada de vídeo deve suportar até 10.000 usuários simultâneos sem degradação do serviço de entrega.

---

## 5. Modelo de Dados Simplificado
* **Usuários:** ID, Nome, Email, CPF, Status_Assinatura.
* **Cursos/Categorias:** ID, Título, Descrição, Thumbnail_URL.
* **Mídias/Aulas:** ID, Curso_ID, Título, Ordem, Bunny_Video_ID, Duracao.
* **Progresso_Video:** ID, Usuario_ID, Midia_ID, Tempo_Segundos, Concluido (Booleano).

---

## 6. Próximos Passos e Roadmap de Implementação
1. **Fase 1:** Setup da conta Bunny.net e configuração da zona de segurança de vídeo (Stream).
2. **Fase 2:** Desenvolvimento da API de Autenticação e Banco de Dados (Gerenciamento de Usuários).
3. **Fase 3:** Criação do Frontend da interface "Netflix" integrado com o player injetado via SDK do Bunny.
4. **Fase 4:** Homologação dos testes de estresse e proteção antipirataria.
