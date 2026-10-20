# The numbers a firm owner cares about, for any period. This is the "proof"
# page: how many rides and how much revenue came through the platform, and
# how many calls were answered that would otherwise have been missed.
class PerformanceReport
  Period = Data.define(:key, :range)

  PERIODS = {
    "7d"  => -> { 6.days.ago.beginning_of_day..Time.current.end_of_day },
    "30d" => -> { 29.days.ago.beginning_of_day..Time.current.end_of_day },
    "90d" => -> { 89.days.ago.beginning_of_day..Time.current.end_of_day },
    "month" => -> { Time.current.all_month }
  }.freeze

  REVENUE_STATUSES = %w[confirmed on_the_way completed].freeze

  attr_reader :tenant, :period

  def initialize(tenant, period_key = "30d")
    @tenant = tenant
    key = PERIODS.key?(period_key) ? period_key : "30d"
    @period = Period.new(key: key, range: PERIODS.fetch(key).call)
  end

  def bookings
    @bookings ||= tenant.bookings.where(created_at: period.range)
  end

  def revenue_bookings
    bookings.where(status: REVENUE_STATUSES)
  end

  def total_bookings = bookings.count
  def completed_count = bookings.completed.count
  def lost_count = bookings.where(status: %w[declined cancelled no_show]).count

  def revenue_cents = sum_revenue(revenue_bookings)
  def platform_revenue_cents = sum_revenue(revenue_bookings.from_platform)

  def average_value_cents
    count = revenue_bookings.where.not(quoted_price_cents: nil).count
    count.zero? ? 0 : revenue_cents / count
  end

  # [{ source:, count:, revenue_cents: }] sorted by revenue.
  def by_source
    Booking::SOURCES.map do |source|
      scope = revenue_bookings.where(source: source)
      { source: source, count: scope.count, revenue_cents: sum_revenue(scope) }
    end.select { |row| row[:count].positive? }.sort_by { |row| -row[:revenue_cents] }
  end

  def calls
    @calls ||= tenant.call_logs.where(created_at: period.range)
  end

  def calls_total = calls.count
  def calls_answered_by_ai = calls.answered_by_ai.count
  def calls_booked = calls.where(outcome: "booked").count

  def call_conversion_rate
    calls_total.zero? ? 0.0 : calls_booked.fdiv(calls_total)
  end

  def empty_legs_published = tenant.empty_legs.where(created_at: period.range).count
  def empty_legs_sold = revenue_bookings.where(source: "empty_leg").count

  def return_trips = revenue_bookings.where(source: "return_trip").count

  def repeat_customer_share
    customer_ids = revenue_bookings.distinct.pluck(:customer_id)
    return 0.0 if customer_ids.empty?

    tenant.customers.where(id: customer_ids).where("bookings_count > 1").count.fdiv(customer_ids.size)
  end

  # Median minutes from booking to dispatcher confirmation (manual only).
  def median_confirmation_minutes
    durations = bookings.where.not(confirmed_at: nil).where(source: Booking::PLATFORM_SOURCES)
                        .pluck(:created_at, :confirmed_at)
                        .map { |created, confirmed| (confirmed - created) / 60.0 }
                        .select(&:positive?).sort
    return nil if durations.empty?

    durations[durations.size / 2].round
  end

  def reviews_requested = bookings.where.not(review_requested_at: nil).count

  # Bookings per day for the bar chart: [[date, count, revenue_cents], ...]
  def daily
    rows = revenue_bookings.pluck(:created_at, :final_price_cents, :quoted_price_cents)
    grouped = rows.group_by { |created, _, _| created.in_time_zone(tenant.time_zone).to_date }
    first = period.range.begin.in_time_zone(tenant.time_zone).to_date
    last = [ period.range.end.in_time_zone(tenant.time_zone).to_date, tenant.now.to_date ].min
    (first..last).map do |day|
      day_rows = grouped.fetch(day, [])
      [ day, day_rows.size, day_rows.sum { |_, final, quoted| final || quoted || 0 } ]
    end
  end

  private
    def sum_revenue(scope)
      scope.sum("COALESCE(final_price_cents, quoted_price_cents, 0)").to_i
    end
end
