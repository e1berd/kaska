defmodule KaskaWeb.ApiSpec do
  @moduledoc """
  Hand-authored OpenAPI 3 description of the agent REST API (`/api/v1`). Served
  as JSON at `/api/openapi` and rendered by Swagger UI at `/api/docs`.
  """

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{
    Components,
    Info,
    MediaType,
    OpenApi,
    Operation,
    Parameter,
    PathItem,
    RequestBody,
    Response,
    Schema,
    SecurityScheme,
    Server
  }

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Kaska Agent API",
        version: "1.0.0",
        description: """
        REST API for automation agents. Authenticate with a personal access
        token (`Authorization: Bearer kaska_pat_…`). The token acts as the
        member that issued it, so access is scoped to that member's projects.

        Task bodies default to Markdown; pass `?task_format=json` to receive the
        raw tiptap document instead.
        """
      },
      servers: [%Server{url: "/api/v1"}],
      paths: paths(),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "Personal access token, e.g. `kaska_pat_…`"
          }
        }
      },
      security: [%{"bearerAuth" => []}]
    }
  end

  defp paths do
    %{
      "/projects" => %PathItem{
        get: %Operation{
          tags: ["Board"],
          operationId: "listProjects",
          summary: "List the projects the token can access",
          responses: %{
            200 => json_response("Projects", array(project_brief_schema()), "projects")
          }
        }
      },
      "/p/{project_slug}" => %PathItem{
        get: %Operation{
          tags: ["Board"],
          operationId: "getProject",
          summary: "Project overview with workflow columns",
          description:
            "Returns the project's `agent_instructions` (free-text guidance for " <>
              "agents) and its columns, each with a `description` explaining when " <>
              "a task belongs in that stage and where to move it next.",
          parameters: [slug_param()],
          responses: %{200 => json_response("Project", project_schema(), "project")}
        }
      },
      "/p/{project_slug}/tasks" => %PathItem{
        get: %Operation{
          tags: ["Tasks"],
          operationId: "listTasks",
          summary: "List all tasks in a project",
          parameters: [slug_param(), format_param()],
          responses: %{200 => json_response("Tasks", array(task_schema()), "tasks")}
        }
      },
      "/p/{project_slug}/tasks/{id}" => %PathItem{
        get: %Operation{
          tags: ["Tasks"],
          operationId: "getTask",
          summary: "Fetch a single task",
          parameters: [slug_param(), id_param(), format_param()],
          responses: %{
            200 => json_response("Task", task_schema(), "task"),
            404 => not_found()
          }
        },
        patch: %Operation{
          tags: ["Tasks"],
          operationId: "updateTask",
          summary: "Update a task",
          description:
            "Send `body` as Markdown, or `body_doc` as a raw tiptap document. " <>
              "Any omitted field is left unchanged.",
          parameters: [slug_param(), id_param(), format_param()],
          requestBody: json_body(task_update_schema()),
          responses: %{
            200 => json_response("Task", task_schema(), "task"),
            404 => not_found(),
            422 => unprocessable()
          }
        }
      },
      "/p/{project_slug}/tasks/{id}/move" => %PathItem{
        post: %Operation{
          tags: ["Tasks"],
          operationId: "moveTask",
          summary: "Move a task to a column",
          description:
            "Moves the task into `column_id`. Without `before_id`/`after_id` " <>
              "the task is appended to the end of the target column.",
          parameters: [slug_param(), id_param()],
          requestBody: json_body(task_move_schema()),
          responses: %{
            200 => json_response("Task", task_schema(), "task"),
            404 => not_found(),
            422 => unprocessable()
          }
        }
      },
      "/p/{project_slug}/tasks/{task_id}/comments" => %PathItem{
        get: %Operation{
          tags: ["Comments"],
          operationId: "listComments",
          summary: "List a task's comments",
          parameters: [slug_param(), task_id_param()],
          responses: %{
            200 => json_response("Comments", array(comment_schema()), "comments"),
            404 => not_found()
          }
        },
        post: %Operation{
          tags: ["Comments"],
          operationId: "createComment",
          summary: "Post a comment on a task",
          description: "Use this to ask questions on a task or report progress.",
          parameters: [slug_param(), task_id_param()],
          requestBody: json_body(comment_create_schema()),
          responses: %{
            201 => json_response("Comment", comment_schema(), "comment"),
            404 => not_found(),
            422 => unprocessable()
          }
        }
      },
      "/p/{project_slug}/columns" => %PathItem{
        get: %Operation{
          tags: ["Board"],
          operationId: "listColumns",
          summary: "List the project's columns (workflow stages)",
          parameters: [slug_param()],
          responses: %{200 => json_response("Columns", array(column_schema()), "columns")}
        }
      },
      "/p/{project_slug}/task_types" => %PathItem{
        get: %Operation{
          tags: ["Board"],
          operationId: "listTaskTypes",
          summary: "List the project's task types",
          parameters: [slug_param()],
          responses: %{
            200 => json_response("Task types", array(task_type_schema()), "task_types")
          }
        }
      },
      "/p/{project_slug}/members" => %PathItem{
        get: %Operation{
          tags: ["Board"],
          operationId: "listMembers",
          summary: "List the project's members",
          parameters: [slug_param()],
          responses: %{200 => json_response("Members", array(user_schema()), "members")}
        }
      }
    }
  end

  ## Parameters ──────────────────────────────────────────────────────────────

  defp slug_param do
    %Parameter{name: :project_slug, in: :path, required: true, schema: %Schema{type: :string}}
  end

  defp id_param do
    %Parameter{
      name: :id,
      in: :path,
      required: true,
      schema: %Schema{type: :string, format: :uuid}
    }
  end

  defp task_id_param do
    %Parameter{
      name: :task_id,
      in: :path,
      required: true,
      schema: %Schema{type: :string, format: :uuid}
    }
  end

  defp format_param do
    %Parameter{
      name: :task_format,
      in: :query,
      required: false,
      description: "Body representation: `md` (default) or `json` (raw tiptap).",
      schema: %Schema{type: :string, enum: ["md", "json"], default: "md"}
    }
  end

  ## Responses ───────────────────────────────────────────────────────────────

  defp json_response(description, schema, key) do
    %Response{
      description: description,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{type: :object, properties: %{key => schema}}
        }
      }
    }
  end

  defp json_body(schema) do
    %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: schema}}
    }
  end

  defp not_found, do: error_response("Resource not found")
  defp unprocessable, do: error_response("Validation failed")

  defp error_response(description) do
    %Response{
      description: description,
      content: %{"application/json" => %MediaType{schema: %Schema{type: :object}}}
    }
  end

  defp array(schema), do: %Schema{type: :array, items: schema}

  ## Schemas ─────────────────────────────────────────────────────────────────

  defp task_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string},
        body: %Schema{
          description: "Markdown string, or a tiptap document when task_format=json.",
          oneOf: [%Schema{type: :string}, %Schema{type: :object}]
        },
        body_format: %Schema{type: :string, enum: ["markdown", "json"]},
        column: column_schema(),
        type: nullable(task_type_schema()),
        assignee: nullable(user_schema()),
        creator: nullable(user_schema()),
        rank: %Schema{type: :string},
        start_date: %Schema{type: :string, format: :date, nullable: true},
        end_date: %Schema{type: :string, format: :date, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        comments: array(comment_schema()),
        attachments: array(attachment_schema())
      }
    }
  end

  defp task_update_schema do
    %Schema{
      type: :object,
      properties: %{
        title: %Schema{type: :string},
        body: %Schema{type: :string, description: "Markdown"},
        body_doc: %Schema{type: :object, description: "Raw tiptap document"},
        assignee_id: %Schema{type: :string, format: :uuid, nullable: true},
        task_type_id: %Schema{type: :string, format: :uuid, nullable: true},
        start_date: %Schema{type: :string, format: :date, nullable: true},
        end_date: %Schema{type: :string, format: :date, nullable: true}
      }
    }
  end

  defp task_move_schema do
    %Schema{
      type: :object,
      required: [:column_id],
      properties: %{
        column_id: %Schema{type: :string, format: :uuid},
        before_id: %Schema{type: :string, format: :uuid, nullable: true},
        after_id: %Schema{type: :string, format: :uuid, nullable: true}
      }
    }
  end

  defp comment_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        task_id: %Schema{type: :string, format: :uuid},
        parent_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Parent comment id when this comment is a reply."
        },
        body: %Schema{
          type: :string,
          description: "Comment body as Markdown, or the raw tiptap document when `?task_format=json`."
        },
        body_format: %Schema{type: :string, enum: ["markdown", "json"]},
        author: nullable(user_schema()),
        guest_name: %Schema{type: :string, nullable: true},
        attachments: array(attachment_schema()),
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      }
    }
  end

  defp comment_create_schema do
    %Schema{
      type: :object,
      required: [:body],
      properties: %{
        body: %Schema{
          type: :string,
          minLength: 1,
          maxLength: 5000,
          description: "Comment body as Markdown. Alternatively send `body_doc` as a raw tiptap document."
        },
        body_doc: %Schema{type: :object, description: "Raw tiptap document (alternative to `body`)."},
        parent_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Reply to this comment. Must belong to the same task."
        }
      }
    }
  end

  defp project_brief_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true}
      }
    }
  end

  defp project_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        agent_instructions: %Schema{
          type: :string,
          nullable: true,
          description: "Project-wide guidance for agents (workflow rules, conventions)."
        },
        columns: array(column_schema())
      }
    }
  end

  defp column_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        rank: %Schema{type: :string},
        description: %Schema{
          type: :string,
          nullable: true,
          description: "What this stage means and where a task moves next."
        }
      }
    }
  end

  defp task_type_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        color: %Schema{type: :string},
        text_color: %Schema{type: :string}
      }
    }
  end

  defp user_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string},
        display_name: %Schema{type: :string, nullable: true}
      }
    }
  end

  defp attachment_schema do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        filename: %Schema{type: :string},
        mime: %Schema{type: :string},
        size: %Schema{type: :integer},
        kind: %Schema{type: :string},
        url: %Schema{type: :string, nullable: true}
      }
    }
  end

  defp nullable(%Schema{} = schema), do: %{schema | nullable: true}
end
