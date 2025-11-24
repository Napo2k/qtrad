from jesse.strategies import Strategy, cached
import jesse.indicators as ta
from jesse import utils

class golden_cross(Strategy):
    @property
    def sma_50(self):
        """50-period Simple Moving Average"""
        return ta.sma(self.candles, 50)

    @property
    def sma_200(self):
        """200-period Simple Moving Average"""
        return ta.sma(self.candles, 200)

    @property
    def atr(self):
        """14-period Average True Range for risk management"""
        return ta.atr(self.candles, 14)

    def should_long(self) -> bool:
        """Golden Cross: SMA(50) crosses above SMA(200)"""
        # Check if golden cross has occurred
        return self.sma_50 > self.sma_200 and self.sma_50[-1] <= self.sma_200[-1]

    def should_short(self) -> bool:
        """Death Cross: SMA(50) crosses below SMA(200)"""
        # Check if death cross has occurred
        return self.sma_50 < self.sma_200 and self.sma_50[-1] >= self.sma_200[-1]

    def should_cancel_entry(self) -> bool:
        """Cancel entry if the cross reverses before execution"""
        return True

    def go_long(self):
        """Execute long position on golden cross"""
        entry_price = self.price
        stop_loss = entry_price - 2 * self.atr
        take_profit = entry_price + 4 * self.atr
        qty = utils.size_to_qty(self.capital * 0.15, entry_price, fee_rate=self.fee_rate) * self.leverage
        
        self.buy = qty, entry_price
        self.stop_loss = qty, stop_loss
        self.take_profit = qty, take_profit

    def go_short(self):
        """Execute short position on death cross"""
        entry_price = self.price
        stop_loss = entry_price + 2 * self.atr
        take_profit = entry_price - 4 * self.atr
        qty = utils.size_to_qty(self.capital * 0.15, entry_price, fee_rate=self.fee_rate) * self.leverage

        self.sell = qty, entry_price
        self.stop_loss = qty, stop_loss
        self.take_profit = qty, take_profit
