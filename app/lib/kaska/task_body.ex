defmodule Kaska.TaskBody do
  @moduledoc """
  Converts task bodies between Markdown and the tiptap (ProseMirror) document
  the editor stores in `tasks.body_doc`.

  The editor schema is `StarterKit` (headings restricted to h2/h3) plus `Link`,
  so the supported vocabulary is bounded:

    * blocks — paragraph, heading, bulletList, orderedList, listItem,
      blockquote, codeBlock, horizontalRule
    * marks — bold, italic, strike, code, link

  Markdown is what the REST API exposes to agents: easy to read, easy to write.
  Anything outside the vocabulary is flattened to its text content rather than
  dropped.
  """

  @empty_doc %{"type" => "doc", "content" => []}

  def empty_doc, do: @empty_doc

  ## API body representation ────────────────────────────────────────────────

  @doc """
  Normalizes a `task_format` / `taskFormat` query value into a format atom.
  Defaults to `:markdown`; only an explicit `json` opts into the raw document.
  """
  def normalize_format(value) when value in ["json", :json], do: :json
  def normalize_format(_), do: :markdown

  @doc """
  Renders a stored `body_doc` for the API in the requested format: a Markdown
  string (`:markdown`) or the raw tiptap document (`:json`).
  """
  def body_view(body_doc, :json), do: body_doc
  def body_view(body_doc, _markdown), do: to_markdown(body_doc)

  ## tiptap → Markdown ──────────────────────────────────────────────────────

  def to_markdown(nil), do: ""

  def to_markdown(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&block_to_md(&1, 0))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def to_markdown(_), do: ""

  defp block_to_md(%{"type" => "paragraph"} = node, _depth), do: inline_to_md(children(node))

  defp block_to_md(%{"type" => "heading"} = node, _depth) do
    level = get_in(node, ["attrs", "level"]) || 2
    String.duplicate("#", level) <> " " <> inline_to_md(children(node))
  end

  defp block_to_md(%{"type" => "bulletList"} = node, depth) do
    node
    |> children()
    |> Enum.map(&list_item_to_md(&1, depth, "- "))
    |> Enum.join("\n")
  end

  defp block_to_md(%{"type" => "orderedList"} = node, depth) do
    start = get_in(node, ["attrs", "start"]) || 1

    node
    |> children()
    |> Enum.with_index(start)
    |> Enum.map(fn {item, index} -> list_item_to_md(item, depth, "#{index}. ") end)
    |> Enum.join("\n")
  end

  defp block_to_md(%{"type" => "blockquote"} = node, depth) do
    node
    |> children()
    |> Enum.map(&block_to_md(&1, depth))
    |> Enum.join("\n\n")
    |> String.split("\n")
    |> Enum.map(&("> " <> &1))
    |> Enum.join("\n")
  end

  defp block_to_md(%{"type" => "codeBlock"} = node, _depth) do
    lang = get_in(node, ["attrs", "language"]) || ""
    body = node |> children() |> Enum.map_join("", &(&1["text"] || ""))
    "```" <> lang <> "\n" <> body <> "\n```"
  end

  defp block_to_md(%{"type" => "horizontalRule"}, _depth), do: "---"

  defp block_to_md(node, _depth), do: inline_to_md(children(node))

  defp list_item_to_md(item, depth, marker) do
    item
    |> children()
    |> Enum.map(&block_to_md(&1, depth + 1))
    |> Enum.join("\n")
    |> apply_marker(marker)
  end

  defp apply_marker(text, marker) do
    pad = String.duplicate(" ", String.length(marker))

    text
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn
      {line, 0} -> marker <> line
      {line, _} -> pad <> line
    end)
    |> Enum.join("\n")
  end

  defp children(node), do: node["content"] || []

  defp inline_to_md(nodes), do: Enum.map_join(nodes, "", &inline_node_to_md/1)

  defp inline_node_to_md(%{"type" => "hardBreak"}), do: "\\\n"

  defp inline_node_to_md(%{"type" => "text", "text" => text} = node) do
    apply_marks(text, node["marks"] || [])
  end

  defp inline_node_to_md(_), do: ""

  defp apply_marks(text, marks) do
    types = Enum.map(marks, & &1["type"])

    if "code" in types do
      wrap_link("`" <> text <> "`", marks)
    else
      text
      |> emphasize("strike", types, "~~")
      |> emphasize("italic", types, "*")
      |> emphasize("bold", types, "**")
      |> wrap_link(marks)
    end
  end

  defp emphasize(text, type, types, wrap) do
    if type in types, do: wrap <> text <> wrap, else: text
  end

  defp wrap_link(text, marks) do
    case Enum.find(marks, &(&1["type"] == "link")) do
      %{"attrs" => %{"href" => href}} when is_binary(href) and href != "" ->
        "[" <> text <> "](" <> href <> ")"

      _ ->
        text
    end
  end

  ## Markdown → tiptap ──────────────────────────────────────────────────────

  def from_markdown(md) when is_binary(md) do
    case MDEx.parse_document(md, extension: [strikethrough: true]) do
      {:ok, %MDEx.Document{nodes: nodes}} ->
        %{"type" => "doc", "content" => Enum.flat_map(nodes, &block_from_md/1)}

      _ ->
        @empty_doc
    end
  end

  def from_markdown(_), do: @empty_doc

  defp block_from_md(%MDEx.Heading{level: level, nodes: nodes}) do
    [
      %{
        "type" => "heading",
        "attrs" => %{"level" => clamp_level(level)},
        "content" => inline_from(nodes)
      }
    ]
  end

  defp block_from_md(%MDEx.Paragraph{nodes: nodes}), do: [paragraph(inline_from(nodes))]

  defp block_from_md(%MDEx.List{list_type: :ordered, start: start, nodes: items}) do
    [
      %{
        "type" => "orderedList",
        "attrs" => %{"start" => start || 1},
        "content" => Enum.map(items, &list_item_from/1)
      }
    ]
  end

  defp block_from_md(%MDEx.List{nodes: items}) do
    [%{"type" => "bulletList", "content" => Enum.map(items, &list_item_from/1)}]
  end

  defp block_from_md(%MDEx.BlockQuote{nodes: nodes}) do
    [%{"type" => "blockquote", "content" => Enum.flat_map(nodes, &block_from_md/1)}]
  end

  defp block_from_md(%MDEx.CodeBlock{literal: literal, info: info}) do
    content =
      case literal do
        value when value in [nil, ""] -> []
        value -> [%{"type" => "text", "text" => String.replace_suffix(value, "\n", "")}]
      end

    [
      %{
        "type" => "codeBlock",
        "attrs" => %{"language" => blank_to_nil(info)},
        "content" => content
      }
    ]
  end

  defp block_from_md(%MDEx.ThematicBreak{}), do: [%{"type" => "horizontalRule"}]

  defp block_from_md(_), do: []

  defp list_item_from(%MDEx.ListItem{nodes: nodes}) do
    case Enum.flat_map(nodes, &block_from_md/1) do
      [] -> %{"type" => "listItem", "content" => [paragraph([])]}
      blocks -> %{"type" => "listItem", "content" => blocks}
    end
  end

  defp list_item_from(_), do: %{"type" => "listItem", "content" => [paragraph([])]}

  defp paragraph([]), do: %{"type" => "paragraph"}
  defp paragraph(content), do: %{"type" => "paragraph", "content" => content}

  defp inline_from(nodes, marks \\ []) do
    nodes |> Enum.flat_map(&inline_node_from(&1, marks)) |> merge_text()
  end

  defp merge_text([%{"type" => "text"} = a, %{"type" => "text"} = b | rest]) do
    if Map.get(a, "marks") == Map.get(b, "marks") do
      merge_text([%{a | "text" => a["text"] <> b["text"]} | rest])
    else
      [a | merge_text([b | rest])]
    end
  end

  defp merge_text([node | rest]), do: [node | merge_text(rest)]
  defp merge_text([]), do: []

  defp inline_node_from(%MDEx.Text{literal: literal}, marks), do: text_node(literal, marks)

  defp inline_node_from(%MDEx.Strong{nodes: nodes}, marks) do
    inline_from(nodes, marks ++ [%{"type" => "bold"}])
  end

  defp inline_node_from(%MDEx.Emph{nodes: nodes}, marks) do
    inline_from(nodes, marks ++ [%{"type" => "italic"}])
  end

  defp inline_node_from(%MDEx.Strikethrough{nodes: nodes}, marks) do
    inline_from(nodes, marks ++ [%{"type" => "strike"}])
  end

  defp inline_node_from(%MDEx.Code{literal: literal}, marks) do
    text_node(literal, marks ++ [%{"type" => "code"}])
  end

  defp inline_node_from(%MDEx.Link{url: url, nodes: nodes}, marks) do
    inline_from(nodes, marks ++ [%{"type" => "link", "attrs" => %{"href" => url}}])
  end

  defp inline_node_from(%MDEx.SoftBreak{}, marks), do: text_node(" ", marks)

  defp inline_node_from(%MDEx.LineBreak{}, _marks), do: [%{"type" => "hardBreak"}]

  defp inline_node_from(other, marks), do: text_node(node_text(other), marks)

  defp text_node(text, _marks) when text in [nil, ""], do: []
  defp text_node(text, []), do: [%{"type" => "text", "text" => text}]
  defp text_node(text, marks), do: [%{"type" => "text", "text" => text, "marks" => marks}]

  defp node_text(%{literal: literal}) when is_binary(literal), do: literal
  defp node_text(%{nodes: nodes}) when is_list(nodes), do: Enum.map_join(nodes, "", &node_text/1)
  defp node_text(_), do: ""

  defp clamp_level(level) when is_integer(level) and level <= 2, do: 2
  defp clamp_level(_), do: 3

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end
end
