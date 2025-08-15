# Strategy Index

This index contains text descriptions for strategies that need to be converted into code.

---

## Convertible Note Strategy

This strategy exploits specific forced market mechanics that effectively put extreme sell pressure on stocks during specific time windows.

### Steps

1. **Company Announcement**: Company issues a press release announcing a convertible note issuance.
2. **Check the Filing**: Look for an exhibit 99.1 attachment in the filing. Identify the pricing window (usually a VWAP during a small timespan on the next trading day).
3. **Open a PUT Contract**: Open a short-duration PUT contract shortly before the pricing window starts (1-2 hours prior).
4. **Sell the PUT**: Sell the PUT shortly after the pricing window starts. Stocks often flatline due to institutional bond hedging.

### Key Insights

- **Mechanics**: Institutional bond hedging causes predictable price action.
- **Pre-Priced Notes**: If the notes are pre-priced, the strategy remains the same as institutions hedge by shorting the underlying stock.
- **Returns**: This strategy can yield consistent 100%+ returns if executed correctly.

---

## Hybrid Strategy

### Longer-Term Swing Trades

- Focus on high-conviction businesses where technical and fundamental setups align.

### Day Trades

- Positions fully opened and closed within market hours.

#### Indicators

- **10-day SMA**: Simple Moving Average.
- **MACD**: Moving Average Convergence Divergence.

#### Rules of Engagement

- Enter long or short when the price breaks above or below the 10-day SMA, confirmed by a bullish or bearish MACD crossover.
- Scale out profits quickly after 1%, 2%, or 3% moves, while letting a portion of the position “run.”

#### Execution

- Trade the underlying stock rather than options.
- Let the last 25% of the position ride until it hits a stop at either your entry or the previous day’s lows.

---

## 200 EMA + Pullbacks

### Step 1: Identify the Direction of the Trend

- Use a **200-session EMA**:
  - Above 200 EMA: Uptrend.
  - Below 200 EMA: Downtrend.

### Step 2: Look for Discounts within the Trend (Pullbacks)

- Use a **20-session EMA** to identify pullbacks:
  - Uptrend: Look for price drops towards the 20 EMA.
  - Downtrend: Look for price increases towards the 20 EMA.

### Step 3: Confirm the End of the Pullback

- Use the **Stochastic Oscillator**:
  - Overbought: Above 80.
  - Oversold: Below 20.
  - Divergence: Price moves in one direction while the Stochastic moves in the opposite.

#### Executing the Strategy

- **Entry**: Enter when the price resumes the main trend after pullback confirmation.
- **Stop Loss**:
  - Downtrend: Place above the previous high.
  - Uptrend: Place below the previous low.
- **Take Profit**: Aim for a minimum risk-reward ratio of 3:1.

---

## Three Candle Strategy

### Pattern Conditions

1. The maximum of two candles prior must be greater than the maximum of one candle prior.
2. The minimum of two candles prior must be less than the minimum of one candle prior.
3. The closing price of the current candle must be higher than the maximum of one candle prior.

### Indicators

- **40-session EMA**.
- **21-session ATR**.

### Trade Execution

- **Entry**: If the three-candle pattern is met and the price is above the 40 EMA, execute a market buy order at the next candle's opening.
- **Stop Loss**: Set at 2x the 21-session ATR.
- **Take Profit**: Use a 2:1 risk-to-reward ratio.

---

## D1 Deceleration + H1 Fibonacci

### Steps

1. **D1 Deceleration**: Identify shrinking daily candle ranges.
2. **H1 Fibonacci**: Calculate swing high/low from the last 8 bars.
3. **M5 MA Break**: Look for a bullish close above the 50 EMA on the 5-minute chart.

### ATR Settings

- Use fixed % targets like “1.5x ATR SL, 2x ATR TP.”

### Risk Per Trade

- Allocate 5% of the account per trade.

---

## Multi Timeframe Strategy

### Entry Conditions

- **Trigger**: Deceleration on the daily chart.
- **Indicators**: 50 EMA and Fibonacci levels on the hourly chart.
- **Execution**: Final entry occurs when the 5-minute chart breaks a moving average.

### Exit Conditions

- Use fixed Stop Loss and Take Profit based on ATR.

### Risk Management

- Position size based on account balance.
- SL and TP defined by ATR or fixed percentages.

---

## BTC Strategies

### Strategy 1: Sudden Bullish Breakouts

- **Entry**: Buy when a 70 EMA crosses above a 160 EMA.
- **Exit**: Close when the 70 EMA crosses below the 160 EMA.
- **Timeframe**: 30 minutes.

### Strategy 2: Quick Pullbacks

- **Entry**: Go long after two consecutive bearish candles above a 20 EMA.
- **Exit**: Close after 140 candles.
- **Timeframe**: 30 minutes.

### Strategy 3: RSI Oversold Conditions

- **Entry**: Buy when RSI < 35, up to 5 positions.
- **Exit**: Close all positions when RSI > 85.
- **Timeframe**: 5 minutes.

---

## Jesse Framework: Pairs-Trading Strategy

### Key Components

- **Asset Selection**: Choose two highly correlated assets (e.g., ETH/ETC).
- **Spread and Z-Score**:
  - Spread: Difference between normalized price returns.
  - Z-Score: Measures how far the spread is from its historical mean.

### Trading Logic

- **Entry**:
  - Long-Short: Z-score < -1.2.
  - Short-Long: Z-score > 1.2.
- **Exit**: Close positions when Z-score returns to zero.

### Risk Management

- **Position Sizing**: Ensure market-neutral positions.
- **Cointegration Check**: Daily check to ensure the pair remains cointegrated.

---

## LW Volatility Breakout Strategy

### Key Components

1. **Donchian Channels**:
   - Length: 96.
   - Used to identify breakout points.
2. **LWTI**:
   - Period: 25.
   - Confirms trend direction.
3. **Volume Indicator**:
   - MA Length: 30.
   - Confirms momentum.

### Trading Rules

- **Long Trade**:
  - Entry: Price touches the upper Donchian band, LWTI is green, and volume is above its MA.
  - Stop Loss: Below the middle Donchian line.
  - Take Profit: 2:1 risk-to-reward ratio.
- **Short Trade**:
  - Entry: Price touches the lower Donchian band, LWTI is red, and volume is above its MA.
  - Stop Loss: Above the middle Donchian line.
  - Take Profit: 2:1 risk-to-reward ratio.

---

## Larry Williams' Trading Strategy

### Rules

- **Timing**: Only trades within the first 12 days of the month. No trades on Fridays. One trade per month.
- **Entry**: Enter when a daily candle closes above the previous day's close.
- **Indicator**: Williams %R must be below -20.

### Exiting

- **Stop Loss**: Fixed 2.5% below the entry point.
- **Take Profit**: Close on the next day's opening after a positive-closing candle.

### Optimizations

1. **ATR Stop-Loss and Take-Profit**:
   - Dynamic stop-loss and take-profit based on ATR.
   - Best Asset: Natural Gas.
   - Result: 70.75% return over 148 trades.
2. **Adjusting Holding Period**:
   - Minimum holding period of 12 candles.
   - Best Asset: Nasdaq 100.
   - Result: 232.84% return over 155 trades.

---

This improved formatting ensures clarity, proper hierarchy, and readability. Let me know if further