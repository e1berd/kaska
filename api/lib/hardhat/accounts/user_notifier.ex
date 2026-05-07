defmodule Hardhat.Accounts.UserNotifier do
  import Swoosh.Email

  alias Hardhat.Mailer

  def deliver_verify_email_instructions(user, url) do
    deliver(user.email, "Подтвердите почту в HardHat", """
    Привет!

    Чтобы подтвердить почту в HardHat, перейди по ссылке:

    #{url}

    Ссылка действует 7 дней. Если ты не регистрировался — просто проигнорируй это письмо.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Сброс пароля HardHat", """
    Привет!

    Чтобы сбросить пароль, перейди по ссылке:

    #{url}

    Ссылка действует 24 часа. Если ты не запрашивал сброс — просто проигнорируй.
    """)
  end

  def deliver_invite_link(email, url) do
    deliver(email, "Приглашение в HardHat", """
    Привет!

    Тебя пригласили в HardHat. Чтобы зарегистрироваться, перейди по ссылке:

    #{url}

    Если ты не знаешь, о чем речь — просто проигнорируй это письмо.
    """)
  end

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"HardHat", System.get_env("MAIL_FROM", "noreply@hardhat.local")})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _meta} <- Mailer.deliver(email), do: {:ok, email}
  end
end
