defmodule VyaasaCampusWeb.DocumentPreviewHTML do
  @moduledoc """
  Standalone pages for viewing a student document that the browser can't render
  on its own.

  A browser renders PDFs, images and plain text inline; a DOCX it can only
  download. Admins open these in a new tab straight from the student drawer, so
  these templates carry their own styling and no app layout — same approach as
  `VyaasaCampusWeb.ErrorHTML`.
  """
  use VyaasaCampusWeb, :html

  embed_templates "document_preview_html/*"
end
