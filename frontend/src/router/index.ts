import { createRouter, createWebHistory, type RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(),
  scrollBehavior: (to, _from, saved) => saved ?? (to.hash ? { el: to.hash, behavior: 'smooth' } : { top: 0 }),
  routes: [
    { path: '/', name: 'home', component: () => import('@/views/IndexView.vue') },
    { path: '/titulo/:slug', name: 'collection', component: () => import('@/views/CollectionView.vue'), props: true, meta: { auth: true } },
    { path: '/buscar', name: 'search', component: () => import('@/views/SearchView.vue'), meta: { auth: true } },
    { path: '/tipo/:kind', name: 'browse', component: () => import('@/views/BrowseView.vue'), props: true, meta: { auth: true } },
    { path: '/genero/:slug', redirect: (to) => ({ name: 'search', query: { genero: String(to.params.slug) } }) },
    { path: '/assistir/:id', name: 'watch', component: () => import('@/views/WatchView.vue'), props: true, meta: { auth: true } },
    { path: '/filme/:id', name: 'movie', component: () => import('@/views/MovieView.vue'), props: true, meta: { auth: true } },
    { path: '/conta', name: 'account', component: () => import('@/views/AccountView.vue'), meta: { auth: true } },
    { path: '/conta/dispositivos', name: 'devices', component: () => import('@/views/DevicesView.vue'), meta: { auth: true } },
    { path: '/entrar', name: 'login', component: () => import('@/views/LoginView.vue'), meta: { guest: true } },
    { path: '/criar-conta', name: 'register', component: () => import('@/views/RegisterView.vue'), meta: { guest: true } },
    { path: '/esqueci-senha', name: 'forgot', component: () => import('@/views/ForgotPasswordView.vue'), meta: { guest: true } },
    { path: '/redefinir-senha/:token', name: 'reset', component: () => import('@/views/ResetPasswordView.vue'), props: true },
    { path: '/confirmar-email/:token', name: 'confirm', component: () => import('@/views/ConfirmEmailView.vue'), props: true },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

// requireAuth / guest-only. `requireSubscription` joins in Fase 2 with Billing.
export async function authGuard(to: RouteLocationNormalized) {
  const auth = useAuthStore()
  await auth.bootstrap()

  if (to.meta.auth && !auth.isAuthenticated) {
    return { name: 'login', query: { next: to.fullPath } }
  }
  if (to.meta.guest && auth.isAuthenticated) return { name: 'home' }
  return true
}

router.beforeEach(authGuard)

export default router
