defmodule Kaska.Agents do
  @moduledoc """
  Agents are bot members of a project: a `Kaska.Accounts.User` with `is_agent`
  set, owned by the human who created it. A bot has a callsign (`display_name`)
  and avatar like any member, so comments and assignments it makes render with
  its own identity. It authenticates over the REST API with a personal access
  token (`Kaska.ApiTokens`).

  Removing an agent unjoins it, revokes its tokens and deletes the user row.
  """

  import Ecto.Query

  alias Kaska.{ApiTokens, Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.Projects.ProjectMember

  def list_agents(project_id) when is_binary(project_id) do
    Repo.all(
      from u in User,
        join: m in ProjectMember,
        on: m.user_id == u.id,
        where: m.project_id == ^project_id and u.is_agent == true,
        order_by: [asc: u.inserted_at]
    )
  end

  def get_agent(project_id, agent_id) when is_binary(project_id) and is_binary(agent_id) do
    Repo.one(
      from u in User,
        join: m in ProjectMember,
        on: m.user_id == u.id,
        where: m.project_id == ^project_id and u.id == ^agent_id and u.is_agent == true
    )
  end

  def get_agent(_, _), do: nil

  @doc """
  Creates a bot member of `project_id` owned by `owner_id` and issues its first
  token. Returns `{:ok, %{agent: user, token: plaintext}}`; the token is shown
  only once.
  """
  def create_agent(owner_id, project_id, attrs)
      when is_binary(owner_id) and is_binary(project_id) do
    Repo.transaction(fn ->
      result = insert_with_token(owner_id, attrs)
      {:ok, _} = Projects.add_member(project_id, result.agent.id, :member)
      result
    end)
  end

  @doc """
  Creates a project-less agent owned by `owner_id` and issues its first token.
  The agent can be assigned to projects later via `assign_to_project/2`.
  """
  def create_owned_agent(owner_id, attrs) when is_binary(owner_id) do
    Repo.transaction(fn -> insert_with_token(owner_id, attrs) end)
  end

  defp insert_with_token(owner_id, attrs) do
    changeset =
      %User{
        email: synthesized_email(),
        hashed_password: unusable_password(),
        is_agent: true,
        agent_owner_id: owner_id,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> User.agent_changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, agent} ->
        {:ok, plaintext, _token} = ApiTokens.create_token(agent, agent.display_name)
        %{agent: agent, token: plaintext}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc "Lists every agent owned by `owner_id`, across all projects."
  def list_for_owner(owner_id) when is_binary(owner_id) do
    Repo.all(
      from u in User,
        where: u.is_agent == true and u.agent_owner_id == ^owner_id,
        order_by: [asc: u.inserted_at]
    )
  end

  def get_owned_agent(owner_id, agent_id) when is_binary(owner_id) and is_binary(agent_id) do
    Repo.one(
      from u in User,
        where: u.is_agent == true and u.agent_owner_id == ^owner_id and u.id == ^agent_id
    )
  end

  def get_owned_agent(_, _), do: nil

  @doc "Projects the agent is currently a member of."
  def agent_projects(agent_id) when is_binary(agent_id) do
    Repo.all(
      from p in Kaska.Projects.Project,
        join: m in ProjectMember,
        on: m.project_id == p.id and m.user_id == ^agent_id,
        order_by: [asc: p.name]
    )
  end

  def assign_to_project(%User{is_agent: true, id: agent_id}, project_id)
      when is_binary(project_id) do
    Projects.add_member(project_id, agent_id, :member)
  end

  def unassign_from_project(%User{is_agent: true} = agent, project_id)
      when is_binary(project_id) do
    remove_agent(project_id, agent)
  end

  def update_agent(%User{is_agent: true} = agent, attrs) do
    agent
    |> User.agent_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Removes the agent from `project_id`. Revokes its tokens only when it no longer
  belongs to any project. Keeps the user row so its past comments keep an author.
  """
  def remove_agent(project_id, %User{is_agent: true, id: agent_id})
      when is_binary(project_id) do
    {:ok, _} = Projects.remove_member(project_id, agent_id)
    unless member_of_any?(agent_id), do: ApiTokens.revoke_all_for_user(agent_id)
    :ok
  end

  @doc "Fully retires the agent: unjoins all projects, revokes all tokens and deletes the user."
  def delete_agent(%User{is_agent: true, id: agent_id} = agent) do
    for project <- agent_projects(agent_id) do
      Projects.remove_member(project.id, agent_id)
    end

    {:ok, _} = ApiTokens.revoke_all_for_user(agent_id)
    Repo.delete!(agent)
    :ok
  end

  defp member_of_any?(agent_id) do
    Repo.exists?(from m in ProjectMember, where: m.user_id == ^agent_id)
  end

  @doc "Revokes the agent's existing tokens and returns a fresh one."
  def regenerate_token(%User{is_agent: true} = agent) do
    {:ok, _} = ApiTokens.revoke_all_for_user(agent.id)
    {:ok, plaintext, _token} = ApiTokens.create_token(agent, agent.display_name)
    {:ok, plaintext}
  end

  defp synthesized_email do
    "agent-" <> random_slug() <> "@agents.kaska.local"
  end

  defp random_slug do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false) |> String.downcase()
  end

  defp unusable_password do
    Bcrypt.hash_pwd_salt(:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))
  end
end
