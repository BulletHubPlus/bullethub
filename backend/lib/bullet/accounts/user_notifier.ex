defmodule Bullet.Accounts.UserNotifier do
  @moduledoc """
  Transactional e-mails. `enqueue/3` inserts an Oban job - call it inside the
  same transaction as the state change (outbox, PRD §4).
  """
  import Swoosh.Email

  alias Bullet.Accounts.User
  alias Bullet.Mailer
  alias Bullet.Workers.DeliverUserEmail

  @kinds ~w(confirmation reset_password)a

  def enqueue(kind, %User{id: user_id}, url) when kind in @kinds do
    %{kind: kind, user_id: user_id, url: url}
    |> DeliverUserEmail.new()
    |> Oban.insert()
  end

  def deliver(:confirmation, user, url) do
    send_email(user, "Confirme seu e-mail", """
    Olá, #{user.name}.

    Confirme seu e-mail no bullethub acessando o link abaixo (válido por 7 dias):

    #{url}

    Se você não criou esta conta, ignore esta mensagem.
    """)
  end

  def deliver(:reset_password, user, url) do
    send_email(user, "Redefinição de senha", """
    Olá, #{user.name}.

    Para redefinir sua senha, acesse o link abaixo (válido por 1 hora):

    #{url}

    Ao redefinir, todos os seus dispositivos serão desconectados.
    Se você não pediu a redefinição, ignore esta mensagem.
    """)
  end

  defp send_email(user, subject, body) do
    email =
      new()
      |> to({user.name, user.email})
      |> from(Application.fetch_env!(:bullet, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _meta} <- Mailer.deliver(email), do: {:ok, email}
  end
end
