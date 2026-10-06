defmodule PolybotWeb.DashboardLive do
  use PolybotWeb, :live_view
  import Ecto.Query
  alias Polybot.Repo
  alias Polybot.Trading.{Decision, Position}

  @refresh_interval 30_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    {:ok, assign(socket, load_data())}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, assign(socket, load_data())}
  end

  defp load_data do
    decisions =
      Repo.all(
        from d in Decision,
          order_by: [desc: d.inserted_at],
          limit: 20
      )

    positions =
      Repo.all(
        from p in Position,
          where: p.status == "open",
          order_by: [desc: p.inserted_at]
      )

    stats = %{
      total_decisions: Repo.aggregate(Decision, :count, :id),
      open_positions: Repo.aggregate(from(p in Position, where: p.status == "open"), :count, :id),
      total_cost:
        Repo.aggregate(from(p in Position, where: p.status == "open"), :sum, :cost) || 0.0
    }

    [decisions: decisions, positions: positions, stats: stats]
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold mb-6">Polybot Dashboard</h1>

      <div class="grid grid-cols-3 gap-4 mb-8">
        <div class="bg-base-200 rounded-lg p-4">
          <div class="text-sm opacity-70">Total Decisions</div>
          <div class="text-3xl font-bold">{@stats.total_decisions}</div>
        </div>
        <div class="bg-base-200 rounded-lg p-4">
          <div class="text-sm opacity-70">Open Positions</div>
          <div class="text-3xl font-bold">{@stats.open_positions}</div>
        </div>
        <div class="bg-base-200 rounded-lg p-4">
          <div class="text-sm opacity-70">Capital Deployed</div>
          <div class="text-3xl font-bold">
            ${:erlang.float_to_binary(@stats.total_cost, decimals: 0)}
          </div>
        </div>
      </div>

      <h2 class="text-xl font-bold mb-4">Open Positions</h2>
      <div class="overflow-x-auto mb-8">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Market</th>
              <th>Action</th>
              <th>Entry Price</th>
              <th>Current Price</th>
              <th>P&L</th>
              <th>Cost</th>
              <th>Opened</th>
            </tr>
          </thead>
          <tbody>
            <%= for position <- @positions do %>
              <tr>
                <td class="max-w-xs truncate">{position.question}</td>
                <td>
                  <span class={[
                    "badge",
                    if(position.action == "buy_yes", do: "badge-success", else: "badge-error")
                  ]}>
                    {position.action}
                  </span>
                </td>
                <td>{position.entry_price}</td>
                <td>{position.exit_price}</td>
                <td class={if (position.pnl || 0) >= 0, do: "text-success", else: "text-error"}>
                  ${Float.round(position.pnl || 0.0, 2)}
                </td>
                <td>${position.cost}</td>
                <td>{Calendar.strftime(position.inserted_at, "%d %b %H:%M")}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <h2 class="text-xl font-bold mb-4">Recent Decisions</h2>
      <div class="overflow-x-auto">
        <table class="table w-full">
          <thead>
            <tr>
              <th>Market</th>
              <th>Action</th>
              <th>Edge</th>
              <th>Confidence</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            <%= for decision <- @decisions do %>
              <tr>
                <td class="max-w-xs truncate">{decision.question}</td>
                <td>
                  <span class={[
                    "badge",
                    cond do
                      decision.action == "buy_yes" -> "badge-success"
                      decision.action == "buy_no" -> "badge-error"
                      true -> "badge-ghost"
                    end
                  ]}>
                    {decision.action}
                  </span>
                </td>
                <td>{Float.round(decision.edge || 0.0, 3)}</td>
                <td>{decision.confidence}</td>
                <td>{Calendar.strftime(decision.inserted_at, "%d %b %H:%M")}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
