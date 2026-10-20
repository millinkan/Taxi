class ApplicationController < ActionController::Base
  include Authentication

  # Note: no `allow_browser versions: :modern` here. The public booking page
  # must work on any phone a customer happens to own; a 406 is a lost fare.

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private
    def render_not_found
      respond_to do |format|
        format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
        format.json { render json: { error: "not_found" }, status: :not_found }
        format.any  { head :not_found }
      end
    end
end
