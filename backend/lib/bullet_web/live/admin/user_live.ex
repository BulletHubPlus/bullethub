defmodule BulletWeb.Admin.UserLive do
  @moduledoc """
  One account for support: plan, devices, recent streams (with watermark codes)
  and security events by period (RF14). Owner/support can suspend (runbook 3:
  revokes every device and drops live streams). Only owner grants plans.
  """
  use BulletWeb, :live_view

  alias Bullet.{Accounts, Billing, Support}

  @periods [{"7 dias", 7}, {"30 dias", 30}, {"90 dias", 90}]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(days: 30, plans: Billing.list_plans()) |> load(id)}
  end

  defp load(socket, id) do
    user = Support.get_user!(id)

    assign(socket,
      user: user,
      page_title: user.name,
      o: Support.overview(user, socket.assigns.days)
    )
  end

  @impl true
  def handle_event("period", %{"days" => days}, socket) do
    {:noreply, socket |> assign(days: String.to_integer(days)) |> load(socket.assigns.user.id)}
  end

  def handle_event("suspend", %{"reason" => reason}, socket) do
    {:ok, _} = Accounts.suspend_user(socket.assigns.user, socket.assigns.current_admin, reason)

    {:noreply,
     socket
     |> put_flash(:info, "Conta suspensa e dispositivos desconectados.")
     |> load(socket.assigns.user.id)}
  end

  def handle_event("unsuspend", _params, socket) do
    case Accounts.unsuspend_user(socket.assigns.user, socket.assigns.current_admin) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Suspensão removida.") |> load(socket.assigns.user.id)}

      {:error, :erased} ->
        {:noreply, put_flash(socket, :error, "Conta apagada (LGPD) não pode ser reativada.")}
    end
  end

  def handle_event("grant", %{"plan" => plan, "days" => days}, socket) do
    if socket.assigns.current_admin.role == :owner do
      {:ok, _} = Billing.grant(socket.assigns.user, plan, String.to_integer(days))
      {:noreply, socket |> put_flash(:info, "Plano concedido.") |> load(socket.assigns.user.id)}
    else
      {:noreply, put_flash(socket, :error, "Só o owner concede planos.")}
    end
  end

  defp fmt(nil), do: "-"
  defp fmt(dt), do: Calendar.strftime(dt, "%d/%m/%Y %H:%M")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, periods: @periods)

    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active={:users}>
      <.link navigate={~p"/usuarios"} class="text-sm text-muted hover:text-base-content">
        ← Usuários
      </.link>
      <.page_header kicker={to_string(@user.role)} title={@user.name} subtitle={@user.email}>
        <:actions>
          <button
            :if={@user.suspended_at && !@user.deleted_at}
            id="unsuspend"
            phx-click="unsuspend"
            class="btn btn-ghost border border-hairline"
          >
            Remover suspensão
          </button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-3">
        <section class="panel p-6">
          <h2 class="sec-label">Conta</h2>
          <dl class="mt-5 grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
            <dt class="text-faint">Criada</dt>
            <dd>{fmt(@user.inserted_at)}</dd>
            <dt class="text-faint">E-mail</dt>
            <dd>{if @user.confirmed_at, do: "confirmado", else: "não confirmado"}</dd>
            <dt class="text-faint">Status</dt>
            <dd id="account-status">
              {cond do
                @user.deleted_at -> "apagada (LGPD)"
                @user.suspended_at -> "suspensa em #{fmt(@user.suspended_at)}"
                true -> "ativa"
              end}
            </dd>
          </dl>
        </section>

        <section class="panel p-6">
          <h2 class="sec-label">Plano</h2>
          <p :if={@o.subscription} class="mt-5 text-sm" id="plan">
            <span class="font-semibold">{@o.subscription.plan.name}</span>
            · {@o.subscription.status} · até {fmt(@o.subscription.current_period_end)}
          </p>
          <p :if={!@o.subscription} class="mt-5 text-sm text-muted" id="plan">Sem plano ativo.</p>

          <form
            :if={@current_admin.role == :owner}
            id="grant-form"
            phx-submit="grant"
            class="mt-5 flex gap-2"
          >
            <select name="plan" class="select select-sm">
              <option :for={p <- @plans} value={p.slug}>{p.name} ({p.max_streams})</option>
            </select>
            <select name="days" class="select select-sm w-24">
              <option value="30">30d</option>
              <option value="90">90d</option>
              <option value="365">365d</option>
            </select>
            <button type="submit" class="btn btn-sm btn-ghost border border-hairline">
              Conceder
            </button>
          </form>
        </section>

        <section :if={!@user.suspended_at} class="panel p-6">
          <h2 class="sec-label">Suspender</h2>
          <form id="suspend-form" phx-submit="suspend" class="mt-5 space-y-3">
            <input
              name="reason"
              placeholder="Motivo (fica no registro de auditoria)"
              class="input input-sm w-full"
              required
            />
            <button
              type="submit"
              class="btn btn-sm w-full border-error/60 bg-transparent text-error hover:bg-error/10"
              data-confirm="Suspender a conta e desconectar todos os dispositivos agora?"
            >
              Suspender e desconectar tudo
            </button>
          </form>
        </section>
      </div>

      <.sec_label index={length(@o.sessions)} label="Sessões recentes" class="mt-12 mb-4" />
      <div class="panel overflow-x-auto">
        <table class="table" id="sessions">
          <thead>
            <tr class="text-faint">
              <th>Código</th>
              <th>Título</th>
              <th>Dispositivo</th>
              <th>IP</th>
              <th>Início</th>
              <th>Fim</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @o.sessions} id={"session-#{s.id}"}>
              <td class="font-mono font-bold text-accent">{s.code}</td>
              <td>{s.media && s.media.title}</td>
              <td>{s.device && s.device.name}</td>
              <td class="text-xs text-faint">{s.ip || "-"}</td>
              <td class="text-xs">{fmt(s.started_at)}</td>
              <td class="text-xs text-faint">{fmt(s.ended_at)} {s.end_reason}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-12 mb-4 flex items-center gap-4">
        <.sec_label index={length(@o.events)} label="Eventos de segurança" class="flex-1" />
        <form id="period-form" phx-change="period">
          <select name="days" class="select select-sm">
            <option :for={{label, d} <- @periods} value={d} selected={d == @days}>{label}</option>
          </select>
        </form>
      </div>
      <div class="panel overflow-x-auto">
        <table class="table" id="events">
          <tbody>
            <tr :if={@o.events == []}>
              <td class="text-muted">Nenhum evento no período.</td>
            </tr>
            <tr :for={e <- @o.events} id={"event-#{e.id}"}>
              <td class="font-semibold">{e.kind}</td>
              <td class="text-xs text-faint">{e.ip}</td>
              <td class="max-w-sm truncate text-xs text-faint">{e.user_agent}</td>
              <td class="text-xs">{fmt(e.inserted_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <.sec_label index={length(@o.devices)} label="Dispositivos" class="mt-12 mb-4" />
      <div class="panel overflow-hidden">
        <div
          :for={d <- @o.devices}
          class="flex items-center gap-4 border-b border-hairline px-6 py-3 text-sm last:border-0"
        >
          <span class="flex-1">{d.name}</span>
          <span class="text-xs text-faint">visto {fmt(d.last_seen_at)}</span>
          <span :if={d.revoked_at} class="text-xs text-faint">revogado</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
