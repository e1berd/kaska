defmodule Kaska.TaskDocs.Seed do
  @moduledoc """
  Seeds a task's collaborative Y.Doc from its `tasks.body_doc` column.

  `TaskDocChannel.handle_in("materialize_body_doc", ...)` only flows one way:
  the live editor's Y.Doc is written into `body_doc` for the REST/agent API
  and card previews to read. A task created outside the editor (`Kaska.TaskBody`,
  used by the agent API) ends up with a real `body_doc` but no `task_docs`
  history at all — the collaborative editor then starts from a brand new,
  empty `Y.Doc` and never shows content that already exists and is readable
  through the API.

  This seeds the reverse direction, once, the first time a task's `Y.Doc` is
  ever materialized (`Kaska.TaskDocs.Server.init/1`) and there is no prior
  snapshot or update history to preserve.

  The mapping mirrors `@tiptap/y-tiptap`'s `prosemirrorToYXmlFragment`
  (`createTypeFromElementNode` / `createTypeFromTextNodes`): each block node
  becomes a `Y.XmlElement` tagged with the node type and carrying its attrs;
  each run of adjacent text nodes becomes one `Y.XmlText` whose marks are
  encoded as Yjs text-formatting attributes (mark type name -> mark attrs, or
  `true` for a mark with no attrs). `@tiptap/extension-collaboration` binds to
  the fragment named `"default"` unless configured otherwise — Kaska's
  `RichEditor.vue` never overrides `field`, so `"default"` is the one that
  matters here.
  """

  @xml_fragment_field "default"

  @doc """
  Seeds `doc`'s `"default"` XML fragment from a ProseMirror/Tiptap `body_doc`
  map. No-ops (returns `false`) when the fragment already has content or
  `body_doc` has nothing to add — safe to call unconditionally.
  """
  @spec seed(Yex.Doc.t(), map() | nil) :: boolean()
  def seed(%Yex.Doc{} = doc, body_doc) do
    nodes = content_of(body_doc)
    fragment = Yex.Doc.get_xml_fragment(doc, @xml_fragment_field)

    if nodes == [] or Yex.XmlFragment.length(fragment) > 0 do
      false
    else
      Enum.each(nodes, &Yex.XmlFragment.push(fragment, node_prelim(&1)))
      true
    end
  end

  defp content_of(%{"type" => "doc", "content" => content}) when is_list(content), do: content
  defp content_of(_), do: []

  defp node_prelim(%{"type" => type} = node) do
    children = node |> content_of_node() |> group_runs() |> Enum.map(&run_prelim/1)
    Yex.XmlElementPrelim.new(type, children, Map.get(node, "attrs", %{}))
  end

  defp content_of_node(%{"content" => content}) when is_list(content), do: content
  defp content_of_node(_), do: []

  # Groups a node's children the way `normalizePNodeContent` does: adjacent
  # text nodes collapse into one run (one Y.XmlText), everything else stays
  # its own element in order.
  defp group_runs([]), do: []

  defp group_runs([%{"type" => "text"} | _] = nodes) do
    {texts, rest} = Enum.split_while(nodes, &(&1["type"] == "text"))
    [{:text, texts} | group_runs(rest)]
  end

  defp group_runs([node | rest]), do: [{:element, node} | group_runs(rest)]

  defp run_prelim({:element, node}), do: node_prelim(node)

  defp run_prelim({:text, texts}) do
    delta =
      Enum.map(texts, fn text ->
        %{insert: text["text"] || "", attributes: marks_to_attributes(text["marks"] || [])}
      end)

    Yex.XmlTextPrelim.from(delta)
  end

  defp marks_to_attributes(marks) do
    Map.new(marks, fn mark -> {mark["type"], Map.get(mark, "attrs", true)} end)
  end
end
