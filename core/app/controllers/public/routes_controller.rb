module Public
  # One landing page per fixed-price route ("Taxi Vaduz - Zurich Airport,
  # CHF 290"): what people search for, and what an assistant can quote.
  class RoutesController < BaseController
    def show
      @route = current_tenant.fixed_routes.active.includes(:origin_place, :destination_place).find(params[:route].to_i)
      return redirect_to(site_path(:route, route: @route.to_param), status: :moved_permanently) if params[:route] != @route.to_param

      @variants = @route.siblings.to_a
    end
  end
end
