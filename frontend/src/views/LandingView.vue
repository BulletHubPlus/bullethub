<script setup lang="ts">
import BrandLink from '@/components/shell/BrandLink.vue'
import bg from '@/assets/login-bg.webp'
import logoFull from '@/assets/logo-full.webp'

const plans = [
  { slug: 'basico', name: 'Básico', screens: 1, perks: ['1 tela por vez', 'Qualidade até 1080p', 'Todo o catálogo'] },
  { slug: 'padrao', name: 'Padrão', screens: 2, perks: ['2 telas ao mesmo tempo', 'Qualidade até 1080p', 'Todo o catálogo'], featured: true },
  { slug: 'familia', name: 'Família', screens: 4, perks: ['4 telas ao mesmo tempo', 'Qualidade até 1080p', 'Todo o catálogo'] },
]

const features = [
  { title: 'Continue de onde parou', body: 'Pausou no notebook? Abra no celular e o vídeo retoma no mesmo ponto.' },
  { title: 'Qualidade que se ajusta', body: 'De 360p a 1080p, automaticamente, conforme a sua conexão. Sem travar.' },
  { title: 'Filmes, séries e animes', body: 'Um catálogo só, organizado por temporadas, com o próximo episódio já na fila.' },
  { title: 'Sua conta sob controle', body: 'Veja onde está conectado e desconecte qualquer dispositivo na hora.' },
]

const faq = [
  { q: 'Posso cancelar quando quiser?', a: 'Sim. Sem fidelidade e sem multa. O acesso continua até o fim do período já pago.' },
  { q: 'Em quais dispositivos funciona?', a: 'No navegador do computador, do celular e do tablet: Chrome, Firefox, Edge e Safari. No celular dá para instalar como app.' },
  { q: 'Quantas pessoas podem assistir ao mesmo tempo?', a: 'Depende do plano: 1, 2 ou 4 telas simultâneas. Você pode encerrar uma tela de outro dispositivo a qualquer momento.' },
  { q: 'Por que pedem CPF no cadastro?', a: 'Para emitir a nota fiscal e evitar contas duplicadas. O CPF fica cifrado e nunca aparece no vídeo.' },
]
</script>

<template>
  <nav class="site-nav" aria-label="Principal">
    <div class="wrap flex h-[72px] items-center gap-8">
      <BrandLink />
      <div class="hidden items-center gap-7 md:flex">
        <a href="#recursos" class="nav-link">Recursos</a>
        <a href="#perguntas" class="nav-link">Perguntas</a>
      </div>
      <div class="ml-auto flex items-center gap-3">
        <RouterLink to="/entrar" class="btn btn-quiet sm">Entrar</RouterLink>
        <a href="#planos" class="btn btn-primary sm">Ver planos</a>
      </div>
    </div>
  </nav>

  <main>
    <!-- hero: copy left, poster wall fading in from the right -->
    <section class="glow-top relative overflow-hidden border-b border-border">
      <div
        class="hero-art pointer-events-none absolute inset-y-0 right-0 hidden w-[62%] bg-cover bg-center opacity-50 lg:block"
        :style="{ backgroundImage: `url(${bg})` }"
        aria-hidden="true"
      />
      <div class="wrap relative grid min-h-[640px] items-center py-24 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.8fr)]">
        <div class="fade-in">
          <p class="kicker"><span class="diamond" />Streaming por assinatura</p>
          <h1 class="display mt-7 max-w-[12ch] text-[3.2rem] sm:text-7xl lg:text-[5.5rem]">
            Filmes, séries e animes. <span class="accent">Sem ruído.</span>
          </h1>
          <p class="lede mt-7 max-w-[46ch] text-lg">
            Assista no navegador ou no celular, continue de onde parou em qualquer tela e cancele quando quiser.
          </p>
          <div class="mt-10 flex flex-wrap items-center gap-4">
            <a href="#planos" class="btn btn-primary">Ver planos <span aria-hidden="true">→</span></a>
            <RouterLink to="/entrar" class="btn-ghost text-sm">Já tenho conta</RouterLink>
          </div>
          <p class="mt-8 text-[13px] text-fg-faint">Sem fidelidade · Até 4 telas · Qualidade até 1080p</p>
        </div>
      </div>
    </section>

    <!-- features -->
    <section id="recursos" class="wrap scroll-mt-24 py-24">
      <h2 class="sec-label"><span class="idx">01</span>Recursos</h2>
      <p class="display mt-8 max-w-[18ch] text-4xl sm:text-5xl">Feito para assistir, <span class="accent">não para esperar.</span></p>
      <div class="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <article v-for="(f, i) in features" :key="f.title" class="card card-accent p-7">
          <span class="text-xs font-bold tabular-nums text-accent">{{ String(i + 1).padStart(2, '0') }}</span>
          <h3 class="mt-5 text-lg">{{ f.title }}</h3>
          <p class="mt-3 text-sm leading-relaxed text-muted-fg">{{ f.body }}</p>
        </article>
      </div>
    </section>

    <!-- plans -->
    <section id="planos" class="scroll-mt-24 border-y border-border bg-[#0a0a0a] py-24">
      <div class="wrap">
        <h2 class="sec-label"><span class="idx">02</span>Planos</h2>
        <div class="mt-8 flex flex-wrap items-end justify-between gap-6">
          <p class="display max-w-[16ch] text-4xl sm:text-5xl">Escolha quantas <span class="accent">telas.</span></p>
          <p class="max-w-[40ch] text-sm text-fg-faint">Todos os planos têm o catálogo completo. A diferença é quantas pessoas assistem ao mesmo tempo.</p>
        </div>

        <div class="mt-14 grid gap-4 md:grid-cols-3">
          <article
            v-for="p in plans"
            :key="p.name"
            class="card flex flex-col p-8"
            :class="{ 'card-accent border-[var(--accent-dim)]': p.featured }"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-xl">{{ p.name }}</h3>
              <span v-if="p.featured" class="kicker !text-[10.5px]">Mais escolhido</span>
            </div>
            <p class="display mt-8 text-6xl tabular-nums">{{ p.screens }}</p>
            <p class="mt-1 text-sm text-fg-faint">{{ p.screens === 1 ? 'tela' : 'telas simultâneas' }}</p>
            <ul class="mt-8 space-y-3 text-sm text-muted-fg">
              <li v-for="perk in p.perks" :key="perk" class="flex items-center gap-3">
                <span class="h-3.5 w-[3px] rounded-full bg-accent" aria-hidden="true" />{{ perk }}
              </li>
            </ul>
            <p class="mt-10 text-sm text-fg-faint">Preço divulgado no lançamento</p>
            <RouterLink
              :to="{ name: 'register', query: { plano: p.slug } }"
              class="btn mt-4"
              :class="p.featured ? 'btn-primary' : 'btn-quiet'"
            >
              Escolher {{ p.name }}
            </RouterLink>
          </article>
        </div>
      </div>
    </section>

    <!-- faq -->
    <section id="perguntas" class="wrap scroll-mt-24 py-24">
      <div class="grid gap-12 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
        <div>
          <h2 class="sec-label"><span class="idx">03</span>Perguntas</h2>
          <p class="display mt-8 max-w-[12ch] text-4xl sm:text-5xl">Antes de <span class="accent">assinar.</span></p>
        </div>
        <div class="border-t border-border">
          <details v-for="item in faq" :key="item.q" class="accordion border-b border-border">
            <summary class="flex items-center justify-between gap-6 py-6 text-lg font-semibold">
              {{ item.q }}
              <span class="acc-plus text-2xl font-light text-accent" aria-hidden="true">+</span>
            </summary>
            <p class="max-w-[60ch] pb-6 text-muted-fg">{{ item.a }}</p>
          </details>
        </div>
      </div>
    </section>

    <!-- closing CTA -->
    <section class="glow-top border-t border-border py-28 text-center">
      <div class="wrap">
        <img :src="logoFull" alt="" class="cta-logo mx-auto -mb-6 w-full max-w-[560px] mix-blend-screen" />
        <p class="kicker justify-center"><span class="diamond" />Pronto?</p>
        <p class="display mx-auto mt-7 max-w-[16ch] text-5xl sm:text-6xl">Sua próxima maratona <span class="accent">começa aqui.</span></p>
        <a href="#planos" class="btn btn-primary mt-10">Escolher um plano <span aria-hidden="true">→</span></a>
      </div>
    </section>
  </main>

  <footer class="border-t border-border py-10">
    <div class="wrap flex flex-wrap items-center justify-between gap-6 text-sm text-fg-faint">
      <BrandLink size="sm" />
      <nav class="flex gap-6" aria-label="Rodapé">
        <a href="#planos" class="hover:text-fg">Planos</a>
        <a href="#perguntas" class="hover:text-fg">Perguntas</a>
        <RouterLink to="/entrar" class="hover:text-fg">Entrar</RouterLink>
      </nav>
      <span>© {{ new Date().getFullYear() }} bullethub</span>
    </div>
  </footer>
</template>

<style scoped>
/* poster wall fades into the black on the left and bottom */
.hero-art {
  mask-image: linear-gradient(to right, transparent 0%, black 45%), linear-gradient(to top, transparent 0%, black 30%);
  mask-composite: intersect;
  -webkit-mask-composite: source-in;
  filter: grayscale(25%);
}

/* the logo's own light streaks fade out at the edges instead of ending in a box */
.cta-logo {
  mask-image: radial-gradient(ellipse 60% 55% at 50% 50%, black 55%, transparent 100%);
}
</style>
