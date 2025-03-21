// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHedgingPlatform
 * @notice Interface for hedging platforms to offset crypto exposure
 */
interface IHedgingPlatform {
    /**
     * @notice Open a short position for an asset
     * @param asset Address of the asset to short
     * @param amount Amount to short
     * @param maxSlippage Maximum acceptable slippage in basis points (1% = 100)
     * @return positionId Unique identifier for the position
     * @return executedAmount Actual amount that was shorted
     */
    function openShortPosition(address asset, uint256 amount, uint256 maxSlippage)
        external
        returns (uint256 positionId, uint256 executedAmount);

    /**
     * @notice Close a short position
     * @param positionId ID of the position to close
     * @param amount Amount of the position to close (0 for full close)
     * @param maxSlippage Maximum acceptable slippage in basis points (1% = 100)
     * @return closedAmount Actual amount that was closed
     * @return pnl Profit or loss from the position (can be negative)
     */
    function closeShortPosition(uint256 positionId, uint256 amount, uint256 maxSlippage)
        external
        returns (uint256 closedAmount, int256 pnl);

    /**
     * @notice Get information about a position
     * @param positionId ID of the position
     * @return asset Asset address
     * @return size Position size
     * @return collateral Collateral amount
     * @return leverage Leverage used (scaled by 1e6)
     * @return liquidationPrice Liquidation price (scaled by 1e18)
     * @return fundingRate Current funding rate (can be negative, scaled by 1e6)
     */
    function getPositionInfo(uint256 positionId)
        external
        view
        returns (
            address asset,
            uint256 size,
            uint256 collateral,
            uint256 leverage,
            uint256 liquidationPrice,
            int256 fundingRate
        );

    /**
     * @notice Add collateral to a position
     * @param positionId ID of the position
     * @param amount Amount of collateral to add
     * @return newLiquidationPrice New liquidation price after adding collateral
     */
    function addCollateral(uint256 positionId, uint256 amount) external returns (uint256 newLiquidationPrice);

    /**
     * @notice Remove collateral from a position
     * @param positionId ID of the position
     * @param amount Amount of collateral to remove
     * @return newLiquidationPrice New liquidation price after removing collateral
     */
    function removeCollateral(uint256 positionId, uint256 amount) external returns (uint256 newLiquidationPrice);

    /**
     * @notice Get current funding rate for an asset
     * @param asset Address of the asset
     * @return fundingRate Current funding rate (can be negative, scaled by 1e6)
     */
    function getFundingRate(address asset) external view returns (int256 fundingRate);
}
