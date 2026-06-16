defmodule Kaska.Accounts.UserNotifier do
  import Swoosh.Email
  require Logger

  alias Kaska.Mailer

  def deliver_verify_email_instructions(user, url) do
    deliver(user.email, "Подтвердите почту в Kaska", """
    Привет!

    Чтобы подтвердить почту в Kaska, перейди по ссылке:

    #{url}

    Ссылка действует 7 дней. Если ты не регистрировался — просто проигнорируй это письмо.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Сброс пароля Kaska", """
    Привет!

    Чтобы сбросить пароль, перейди по ссылке:

    #{url}

    Ссылка действует 24 часа. Если ты не запрашивал сброс — просто проигнорируй.
    """)
  end

  def deliver_invite_link(email, url) do
    deliver(email, "Приглашение в Kaska", """
    Привет!

    Тебя пригласили в Kaska. Чтобы зарегистрироваться, перейди по ссылке:

    #{url}

    Если ты не знаешь, о чем речь — просто проигнорируй это письмо.
    """)
  end

  def deliver_project_invite_link(email, project_name, url) do
    deliver(email, "Приглашение в проект «#{project_name}» — Kaska", """
    Привет!

    Тебя пригласили в проект «#{project_name}» в Kaska. Чтобы присоединиться, перейди по ссылке:

    #{url}

    Если ты не знаешь, о чем речь — просто проигнорируй это письмо.
    """)
  end

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from(
        {System.get_env("MAIL_FROM_NAME", "Kaska"),
         System.get_env("MAIL_FROM_ADDRESS", "noreply@kaska.local")}
      )
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, meta} ->
        Logger.info("[mail] sent to=#{to} subject=#{inspect(subject)} meta=#{inspect(meta)}")
        {:ok, email}

      {:error, reason} ->
        Logger.error(
          "[mail] FAILED to=#{to} subject=#{inspect(subject)} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
