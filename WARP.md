# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Repository Overview

Qtrad is a comprehensive algorithmic trading repository focused on strategy development, backtesting, and deployment across multiple platforms including MetaTrader 5, TradingView, and various broker APIs. The repository combines manual strategy research with AI-assisted code generation for trading systems.

## High-Level Architecture

### Core Components

1. **Strategy Development Pipeline**:
   - **StrategyQuant** (.mq5 files): Generated MT5 Expert Advisors in `squant/` directory
   - **Manual Strategies** (`strategies.md`): Text descriptions of trading strategies for AI conversion
   - **AI Prompts** (`AI_prompts.md`): Detailed prompts for generating trading bots and EAs

2. **Research & Analysis**:
   - **Jupyter Notebooks**: Interactive analysis for different asset classes (eth.ipynb, oanda.ipynb, ib.ipynb, rsi.ipynb, trend.ipynb)
   - **TradingView Pine Scripts**: Custom indicators and strategies in `tv/` directory

3. **Trading Infrastructure**:
   - **IBJts/**: Interactive Brokers TWS API C++ client library
   - **trading_library/**: Python broker API client framework (`client.py`)

4. **Platform Integrations**:
   - MetaTrader 5 Expert Advisors (MQL5)
   - TradingView Pine Script indicators
   - Interactive Brokers TWS API
   - Generic broker API wrapper

## Common Development Commands

### Interactive Brokers C++ API

```bash
# Build the TWS API library
cd IBJts
mkdir build && cd build
cmake ..
make

# Build with debug symbols
cmake -DCMAKE_BUILD_TYPE=Debug ..
make

# Build with test client
cmake -DIBKR_BUILD_TESTCPPCLIENT=TRUE ..
make

# Run linter
cmake -DENABLE_LINTER=ON ..
make

# Format code
make format
```

### Python Development

```bash
# Set up Python virtual environment
python3 -m venv .env
source .env/bin/activate

# Install dependencies (if requirements.txt exists)
pip install -r requirements.txt

# Run Jupyter notebooks
jupyter lab

# For specific notebook analysis
jupyter nbconvert --to python eth.ipynb --stdout | python
```

### Strategy Development Workflow

```bash
# Generate new MQL5 strategy from AI prompt
# 1. Add strategy description to strategies.md
# 2. Use AI_prompts.md templates to generate MQL5 code
# 3. Save generated .mq5 files to squant/ directory

# Convert strategy description to code using AI
# Reference specific sections from AI_prompts.md:
# - Section 2: 9 EMA-Based Expert Advisor
# - Section 3: Multi-Timeframe Forex Robot
# - Section 4: Advanced Forex Trading Robot
# - Section 5: High-Frequency Trading Bot
```

### TradingView Development

```bash
# Pine Script files are in tv/ directory
# - ema_crossover.pine: EMA crossover strategy
# - market-sd-claude.pine: Market standard deviation indicator
# - zigzag.pine: ZigZag indicator
# - zigzag_strategy.pine: ZigZag-based trading strategy

# To deploy: Copy .pine files to TradingView Pine Editor
```

## Development Patterns

### Strategy Conversion Process

1. **Research Phase**: Document strategy in `strategies.md` with:
   - Entry/exit conditions
   - Risk management rules
   - Timeframes and indicators
   - Expected performance metrics

2. **AI Generation**: Use templates from `AI_prompts.md` to:
   - Generate MQL5 Expert Advisors for MT5
   - Create Pine Script versions for TradingView
   - Build Python implementations using `trading_library/`

3. **Testing Phase**: Use Jupyter notebooks for:
   - Backtesting with historical data
   - Parameter optimization
   - Performance analysis
   - Risk assessment

4. **Deployment**: 
   - MT5: Deploy .mq5 files to MetaTrader 5
   - TradingView: Upload .pine scripts
   - Live Trading: Use `trading_library/client.py` for broker integration

### Code Organization

- **squant/**: Contains numbered strategy versions (e.g., "Strategy 2.30.191.mq5")
- **tv/**: TradingView Pine Script implementations
- **trading_library/**: Reusable Python trading components
- **IBJts/**: C++ TWS API for Interactive Brokers integration
- Jupyter notebooks for research and backtesting specific to asset classes

### Strategy Naming Convention

MQL5 strategies follow pattern: `Strategy X.Y.Z.mq5` where:
- X: Major strategy version/family
- Y: Minor version with parameter changes
- Z: Build number for bug fixes

## Key Technical Details

### Interactive Brokers Integration

- Uses TWS API C++ client library
- CMake build system with C++11 standard
- Supports both debug and release builds
- Includes clang-tidy linting support
- Cross-platform compatibility

### Python Trading Framework

- Generic broker API client in `trading_library/client.py`
- Supports account info, ticker data, order placement, position management
- Configurable via environment variables or config module
- Error handling and request retry logic

### Multi-Platform Strategy Deployment

The repository is designed for cross-platform strategy deployment:
- **MetaTrader 5**: MQL5 Expert Advisors (.mq5)
- **TradingView**: Pine Script indicators/strategies (.pine)
- **Python/API**: Direct broker integration via REST APIs
- **C++/TWS**: High-performance Interactive Brokers integration

## Research and Development Workflow

1. **Strategy Research**: Use Jupyter notebooks to analyze market data and test concepts
2. **Strategy Documentation**: Document findings in `strategies.md`
3. **AI-Assisted Coding**: Use prompts from `AI_prompts.md` to generate initial implementations
4. **Multi-Platform Deployment**: Convert strategies to MQL5, Pine Script, and Python as needed
5. **Backtesting**: Validate strategies using historical data in notebooks
6. **Live Testing**: Deploy with small capital using broker APIs
