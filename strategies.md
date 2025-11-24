# Strategy Index

This index contains text descriptions for strategies that need to be converted into code.

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
  - **Overbought**: Above 80.
  - **Oversold**: Below 20.
  - **Divergence**: Price moves in one direction while the Stochastic moves in the opposite.

### Executing the Strategy

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
  - **Spread**: Difference between normalized price returns.
  - **Z-Score**: Measures how far the spread is from its historical mean.

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
  - **Entry**: Price touches the upper Donchian band, LWTI is green, and volume is above its MA.
  - **Stop Loss**: Below the middle Donchian line.
  - **Take Profit**: 2:1 risk-to-reward ratio.
- **Short Trade**:
  - **Entry**: Price touches the lower Donchian band, LWTI is red, and volume is above its MA.
  - **Stop Loss**: Above the middle Donchian line.
  - **Take Profit**: 2:1 risk-to-reward ratio.

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
   - **Best Asset**: Natural Gas.
   - **Result**: 70.75% return over 148 trades.
2. **Adjusting Holding Period**:
   - Minimum holding period of 12 candles.
   - **Best Asset**: Nasdaq 100.
   - **Result**: 232.84% return over 155 trades.

---

## Systematic Trading Strategy

This strategy introduces a systematic trading approach with only three entry and exit rules, claiming a **62% win rate** with low market exposure. The strategy is based on the book *Short-Term Strategies That Work* by Larry Connors and is designed for the **daily timeframe**. The video by David demonstrates the strategy's code, backtest results on different ETFs, and explains how to increase its net profit.

### Trading Strategy Details

#### Entry Rules

1. The current **closing price** must be below the **previous seven-day low**.
2. The market must be trading **above its 200-day moving average**.
3. A **stop-loss** is set at a size equal to **twice the average true range (ATR)** of the past 20 bars.

#### Exit Rules

- The position is closed when the market closes **above its previous seven-day high**.

### Backtest Results

The strategy was backtested from **2007 to 2020** on four different ETFs: **SPY**, **TLT**, **GLD**, and **VNQ**.

- **Average Annual Return**: 7.5%
- **Maximum Drawdown**: 10%
- **Market Exposure**: The strategy was only in a trade about **20% of the time**, resulting in approximately **25-26 trades per year**.

### Futures Trading Results

Applying the same strategy to **futures** instead of ETFs significantly increased the total profit:

- **Total Profit**: Increased from $17,000 to $74,000.
- **Average Annual Return**: Raised to almost **17%**.
- **Drawdown**: Higher maximum drawdown due to the increased leverage of futures trading.

---

## Opening Range Breakout Strategy

This strategy is a day trading approach focused on the first two hours of the New York market session, designed to capitalize on breakouts from a defined opening range.

### Steps

1. **Identify the Opening Range**: Mark the high and low of the first 15-minute candle of the New York session (9:30 AM EST).
2. **Wait for a Breakout**: Wait for a 5-minute candle to close either above the 15-minute range high or below the low.
3. **Find Entry on the 1-Minute Chart**:
   - **Breakout**: Enter immediately after the strong candle closes outside the range.
   - **Retest**: Wait for the price to pull back and retest the opening range level before continuing in the breakout direction.
   - **Reversal**: If the breakout fails and the price moves back into the range, look for a reversal entry on a retest of the opposite side of the range.

---

## EMA Pullback Strategy

This is a simple day trading strategy for beginners that uses the 50-day Exponential Moving Average (EMA) to identify entry points after a pullback.

### For a Long (Buy) Position

1. **Entry**: Wait for a candle to close above the 50 EMA. Then, wait for a pullback of at least two consecutive red candles. Draw a horizontal line at the swing high before the pullback, and enter a buy when a candle's body closes above that line.
2. **Exit**:
   - **Stop Loss**: Use the Chandelier Stop indicator.
   - **Take Profit**: Set at a 2:1 risk-to-reward ratio.

### For a Short (Sell) Position

1. **Entry**: The rules are the same but in reverse. Wait for a candle to close below the 50 EMA, wait for a pullback of at least two consecutive green candles, draw a horizontal line at the swing low, and enter a sell when a candle's body closes below that line.
