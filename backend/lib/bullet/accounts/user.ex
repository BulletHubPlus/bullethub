defmodule Bullet.Accounts.User do
  @moduledoc false
  use Bullet.Schema

  @type t :: %__MODULE__{}

  alias Bullet.Accounts.CPF

  @roles [:subscriber, :support, :editor, :owner]

  @derive {Inspect, except: [:password, :password_hash, :cpf, :cpf_encrypted, :cpf_hash]}
  schema "users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :cpf, :string, virtual: true, redact: true
    field :cpf_encrypted, Bullet.Encrypted.Binary, redact: true
    field :cpf_hash, :binary, redact: true
    field :role, Ecto.Enum, values: @roles, default: :subscriber
    field :confirmed_at, :utc_datetime_usec
    field :suspended_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    has_many :devices, Bullet.Accounts.Device

    timestamps()
  end

  def roles, do: @roles

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password, :cpf])
    |> validate_required([:email, :name, :password, :cpf])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_email()
    |> validate_cpf()
    |> validate_password()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
  end

  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now())
  end

  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    # Constant-ish time on unknown e-mail, so login timing doesn't enumerate accounts.
    Argon2.no_user_verify()
    false
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/, message: "inválido")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Bullet.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    # Hash last and only when valid: Argon2 is deliberately expensive.
    if changeset.valid? and is_binary(password) do
      changeset
      |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp validate_cpf(changeset) do
    changeset
    |> validate_change(:cpf, fn :cpf, cpf ->
      if CPF.valid?(cpf), do: [], else: [cpf: "inválido"]
    end)
    |> then(fn cs ->
      case {cs.valid?, get_change(cs, :cpf)} do
        {true, cpf} when is_binary(cpf) ->
          digits = CPF.normalize(cpf)

          cs
          |> put_change(:cpf_encrypted, digits)
          |> put_change(:cpf_hash, CPF.hash(digits))
          |> delete_change(:cpf)

        _ ->
          cs
      end
    end)
    |> unique_constraint(:cpf, name: :users_cpf_hash_index, message: "já cadastrado")
  end
end
