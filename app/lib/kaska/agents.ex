defmodule Kaska.Agents do
  @moduledoc """
  Agents are bot users (`Kaska.Accounts.User` with `is_agent`) owned by the
  human who created them. An agent has a name and avatar like any member, is
  assigned to the owner's projects, and works on tasks through server-side runs
  (`Kaska.AgentRuntime`). Agents have no long-lived credentials: each run gets
  its own short-lived token.
  """

  import Ecto.Query

  alias Kaska.{Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.Projects.{Project, ProjectMember}

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

  @doc "Creates a project-less agent owned by `owner_id`."
  def create_agent(owner_id, attrs) when is_binary(owner_id) do
    %User{
      email: synthesized_email(),
      hashed_password: unusable_password(),
      is_agent: true,
      agent_owner_id: owner_id,
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    |> User.agent_changeset(attrs)
    |> Repo.insert()
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
    case Ecto.UUID.cast(agent_id) do
      {:ok, _} ->
        Repo.one(
          from u in User,
            where: u.is_agent == true and u.agent_owner_id == ^owner_id and u.id == ^agent_id
        )

      :error ->
        nil
    end
  end

  def get_owned_agent(_, _), do: nil

  @doc "Projects the agent is currently a member of."
  def agent_projects(agent_id) when is_binary(agent_id) do
    Repo.all(
      from p in Project,
        join: m in ProjectMember,
        on: m.project_id == p.id and m.user_id == ^agent_id,
        order_by: [asc: p.name]
    )
  end

  def assign_to_project(%User{is_agent: true, id: agent_id}, project_id)
      when is_binary(project_id) do
    Projects.add_member(project_id, agent_id, :member)
  end

  def unassign_from_project(%User{is_agent: true, id: agent_id}, project_id)
      when is_binary(project_id) do
    {:ok, _} = Projects.remove_member(project_id, agent_id)
    :ok
  end

  def update_agent(%User{is_agent: true} = agent, attrs) do
    agent
    |> User.agent_changeset(attrs)
    |> Repo.update()
  end

  @doc "Unjoins the agent from all projects and deletes it. Past comments keep no author."
  def delete_agent(%User{is_agent: true, id: agent_id} = agent) do
    for project <- agent_projects(agent_id) do
      Projects.remove_member(project.id, agent_id)
    end

    Repo.delete!(agent)
    :ok
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
