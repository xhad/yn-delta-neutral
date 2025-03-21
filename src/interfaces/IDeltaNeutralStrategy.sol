// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDeltaNeutralStrategy
 * @notice Interface for the delta-neutral strategy controller
 */
interface IDeltaNeutralStrategy {
    /// @notice Asset types supported by the strategy
    enum AssetType {
        ETH,
        BTC,
        USD
    }

    /// @notice Position types for the strategy
    enum PositionType {
        YIELD,
        HEDGE,
        STABLE
    }

    /// @notice Structure to track a yield-bearing position
    struct YieldPosition {
        address asset;
        uint256 amount;
        uint256 value;
        AssetType assetType;
    }

    /// @notice Structure to track a hedging position
    struct HedgePosition {
        address asset;
        uint256 amount;
        uint256 value;
        bool isShort;
        int256 fundingRate; // Can be negative, represented as a signed integer
    }

    /// @notice Structure to track a stablecoin position
    struct StablePosition {
        address asset;
        uint256 amount;
        uint256 value;
        address yieldProtocol;
    }

    /// @notice Structure representing the portfolio state
    struct Portfolio {
        YieldPosition[] yieldPositions;
        HedgePosition[] hedgePositions;
        StablePosition[] stablePositions;
        mapping(AssetType => int256) netExposure; // Can be negative
        uint256 totalValue;
    }

    /// @notice Event emitted when depositing to a yield-bearing asset
    event DepositToYieldAsset(address indexed asset, uint256 amount, address indexed user);
    
    /// @notice Event emitted when creating a hedge position
    event HedgePositionCreated(address indexed asset, uint256 amount, bool isShort);
    
    /// @notice Event emitted when deploying stablecoins to yield protocols
    event StableDeployed(address indexed asset, uint256 amount, address indexed protocol);
    
    /// @notice Event emitted when rebalancing the portfolio
    event PortfolioRebalanced(int256 ethExposure, int256 btcExposure, int256 usdExposure);

    /**
     * @notice Deposit tokens to yield-bearing assets
     * @param assetType Type of asset to deposit
     * @param amount Amount to deposit
     * @return success Whether the deposit was successful
     */
    function depositToYieldBearingAsset(AssetType assetType, uint256 amount) external returns (bool success);
    
    /**
     * @notice Create a hedging position to offset exposure
     * @param assetType Type of asset to hedge
     * @param amount Amount to hedge
     * @param isShort Whether the position is short (true) or long (false)
     * @return success Whether the hedge position was created successfully
     */
    function createHedgePosition(AssetType assetType, uint256 amount, bool isShort) external returns (bool success);
    
    /**
     * @notice Deploy stablecoins to a yield-generating protocol
     * @param protocol Address of the yield protocol
     * @param amount Amount to deploy
     * @return success Whether the deployment was successful
     */
    function deployStableToYieldProtocol(address protocol, uint256 amount) external returns (bool success);
    
    /**
     * @notice Check if portfolio needs rebalancing
     * @return needsRebalance Whether rebalancing is needed
     */
    function needsRebalancing() external view returns (bool needsRebalance);
    
    /**
     * @notice Rebalance the portfolio to maintain delta neutrality
     * @return success Whether the rebalance was successful
     */
    function rebalance() external returns (bool success);
    
    /**
     * @notice Calculate estimated APR based on current positions
     * @return apr The estimated APR in basis points (1% = 100 basis points)
     */
    function calculateEstimatedAPR() external view returns (uint256 apr);
    
    /**
     * @notice Get the current portfolio state summary
     * @return totalValue Total portfolio value
     * @return ethExposure Net ETH exposure
     * @return btcExposure Net BTC exposure
     * @return usdExposure Net USD exposure
     */
    function getPortfolioSummary() external view returns (
        uint256 totalValue,
        int256 ethExposure,
        int256 btcExposure,
        int256 usdExposure
    );
} 