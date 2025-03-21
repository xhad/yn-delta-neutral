// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/IDeltaNeutralStrategy.sol";
import "./interfaces/IYieldToken.sol";
import "./interfaces/IHedgingPlatform.sol";
import "./interfaces/IYieldProtocol.sol";

/**
 * @title DeltaNeutralStrategy
 * @notice Implementation of a delta-neutral strategy using ynETHx, ynBTCx, and ynUSDx
 */
contract DeltaNeutralStrategy is IDeltaNeutralStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Constants
    uint256 public constant BASIS_POINTS = 10000; // 100%
    uint256 public constant PRECISION = 1e18;
    uint256 public constant REBALANCE_THRESHOLD = 500; // 5% deviation threshold
    uint256 public constant MAX_SLIPPAGE = 100; // 1% max slippage

    // Asset addresses
    address public immutable ynETHxAddress;
    address public immutable ynBTCxAddress;
    address public immutable ynUSDxAddress;
    address public immutable wethAddress;
    address public immutable wbtcAddress;

    // Platform addresses
    address public hedgingPlatformAddress;
    
    // Portfolio state
    mapping(uint256 => HedgePosition) public hedgePositions; // positionId => HedgePosition
    mapping(address => uint256[]) public userHedgePositions; // user => positionIds
    uint256 public nextPositionId;
    
    // Platform state
    mapping(address => bool) public approvedYieldProtocols;
    
    // Portfolio parameters
    uint256 public rebalanceThreshold; // Basis points
    uint256 public targetETHAllocation; // Basis points
    uint256 public targetBTCAllocation; // Basis points
    uint256 public targetUSDAllocation; // Basis points
    
    // Portfolio mapping
    mapping(address => mapping(AssetType => YieldPosition[])) private userYieldPositions;
    mapping(address => mapping(address => StablePosition[])) private userStablePositions;

    // Events
    event StrategyDeployed(address indexed owner, address ynETHx, address ynBTCx, address ynUSDx);
    event YieldProtocolAdded(address indexed protocol);
    event YieldProtocolRemoved(address indexed protocol);
    event HedgingPlatformSet(address indexed platform);
    event AllocationUpdated(uint256 ethAllocation, uint256 btcAllocation, uint256 usdAllocation);

    /**
     * @notice Constructor to initialize the contract
     * @param _ynETHxAddress Address of the ynETHx token
     * @param _ynBTCxAddress Address of the ynBTCx token
     * @param _ynUSDxAddress Address of the ynUSDx token
     * @param _wethAddress Address of the WETH token
     * @param _wbtcAddress Address of the WBTC token
     * @param _hedgingPlatform Address of the hedging platform
     * @param _ethAllocation Target ETH allocation in basis points
     * @param _btcAllocation Target BTC allocation in basis points
     * @param _usdAllocation Target USD allocation in basis points
     */
    constructor(
        address _ynETHxAddress,
        address _ynBTCxAddress,
        address _ynUSDxAddress,
        address _wethAddress,
        address _wbtcAddress,
        address _hedgingPlatform,
        uint256 _ethAllocation,
        uint256 _btcAllocation,
        uint256 _usdAllocation
    ) Ownable(msg.sender) {
        require(_ynETHxAddress != address(0), "Invalid ynETHx address");
        require(_ynBTCxAddress != address(0), "Invalid ynBTCx address");
        require(_ynUSDxAddress != address(0), "Invalid ynUSDx address");
        require(_wethAddress != address(0), "Invalid WETH address");
        require(_wbtcAddress != address(0), "Invalid WBTC address");
        require(_hedgingPlatform != address(0), "Invalid hedging platform");
        require(_ethAllocation + _btcAllocation + _usdAllocation == BASIS_POINTS, "Invalid allocations");
        
        ynETHxAddress = _ynETHxAddress;
        ynBTCxAddress = _ynBTCxAddress;
        ynUSDxAddress = _ynUSDxAddress;
        wethAddress = _wethAddress;
        wbtcAddress = _wbtcAddress;
        hedgingPlatformAddress = _hedgingPlatform;
        
        targetETHAllocation = _ethAllocation;
        targetBTCAllocation = _btcAllocation;
        targetUSDAllocation = _usdAllocation;
        
        rebalanceThreshold = REBALANCE_THRESHOLD;
        nextPositionId = 1;
        
        emit StrategyDeployed(msg.sender, ynETHxAddress, ynBTCxAddress, ynUSDxAddress);
        emit HedgingPlatformSet(hedgingPlatformAddress);
        emit AllocationUpdated(targetETHAllocation, targetBTCAllocation, targetUSDAllocation);
    }

    /**
     * @notice Deposit tokens to yield-bearing assets
     * @param assetType Type of asset to deposit
     * @param amount Amount to deposit
     * @return success Whether the deposit was successful
     */
    function depositToYieldBearingAsset(AssetType assetType, uint256 amount) external override nonReentrant returns (bool success) {
        require(amount > 0, "Amount must be greater than zero");
        
        address yieldTokenAddress;
        uint256 depositAmount = amount;
        
        if (assetType == AssetType.ETH) {
            yieldTokenAddress = ynETHxAddress;
            // Transfer WETH from the user
            IERC20(wethAddress).safeTransferFrom(msg.sender, address(this), amount);
            // Approve WETH for ynETHx
            IERC20(wethAddress).approve(yieldTokenAddress, amount);
        } else if (assetType == AssetType.BTC) {
            yieldTokenAddress = ynBTCxAddress;
            // Transfer WBTC from the user
            IERC20(wbtcAddress).safeTransferFrom(msg.sender, address(this), amount);
            // Approve WBTC for ynBTCx
            IERC20(wbtcAddress).approve(yieldTokenAddress, amount);
        } else if (assetType == AssetType.USD) {
            yieldTokenAddress = ynUSDxAddress;
            // Get the underlying asset of ynUSDx (e.g., USDC)
            address underlyingAsset = IYieldToken(yieldTokenAddress).underlyingAsset();
            // Transfer stablecoin from the user
            IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), amount);
            // Approve stablecoin for ynUSDx
            IERC20(underlyingAsset).approve(yieldTokenAddress, amount);
        } else {
            revert("Invalid asset type");
        }
        
        // Deposit into the yield token contract
        uint256 mintedAmount = IYieldToken(yieldTokenAddress).deposit(depositAmount);
        require(mintedAmount > 0, "Deposit failed");
        
        // Create a yield position
        YieldPosition memory yieldPosition = YieldPosition({
            asset: yieldTokenAddress,
            amount: mintedAmount,
            value: _getValueInUSD(yieldTokenAddress, mintedAmount),
            assetType: assetType
        });
        
        // Add to user's portfolio
        userYieldPositions[msg.sender][assetType].push(yieldPosition);
        
        emit DepositToYieldAsset(yieldTokenAddress, amount, msg.sender);
        
        return true;
    }

    /**
     * @notice Create a hedging position to offset exposure
     * @param assetType Type of asset to hedge
     * @param amount Amount to hedge
     * @param isShort Whether the position is short (true) or long (false)
     * @return success Whether the hedge position was created successfully
     */
    function createHedgePosition(AssetType assetType, uint256 amount, bool isShort) external override nonReentrant returns (bool success) {
        require(amount > 0, "Amount must be greater than zero");
        require(isShort, "Only short positions are supported currently");
        
        address asset;
        if (assetType == AssetType.ETH) {
            asset = wethAddress;
        } else if (assetType == AssetType.BTC) {
            asset = wbtcAddress;
        } else {
            revert("Cannot hedge USD assets");
        }
        
        // Interact with the hedging platform
        IHedgingPlatform hedgingPlatform = IHedgingPlatform(hedgingPlatformAddress);
        
        // Approve asset for hedging platform
        IERC20(asset).approve(hedgingPlatformAddress, amount);
        
        // Open short position
        (uint256 positionId, uint256 executedAmount) = hedgingPlatform.openShortPosition(
            asset,
            amount,
            MAX_SLIPPAGE
        );
        
        // Get position details
        (
            ,
            uint256 size,
            uint256 collateral,
            uint256 leverage,
            uint256 liquidationPrice,
            int256 fundingRate
        ) = hedgingPlatform.getPositionInfo(positionId);
        
        // Create hedge position
        HedgePosition memory hedgePosition = HedgePosition({
            asset: asset,
            amount: executedAmount,
            value: _getValueInUSD(asset, executedAmount),
            isShort: isShort,
            fundingRate: fundingRate
        });
        
        // Store position
        hedgePositions[positionId] = hedgePosition;
        userHedgePositions[msg.sender].push(positionId);
        nextPositionId++;
        
        emit HedgePositionCreated(asset, executedAmount, isShort);
        
        return true;
    }

    /**
     * @notice Deploy stablecoins to a yield-generating protocol
     * @param protocol Address of the yield protocol
     * @param amount Amount to deploy
     * @return success Whether the deployment was successful
     */
    function deployStableToYieldProtocol(address protocol, uint256 amount) external override nonReentrant returns (bool success) {
        require(approvedYieldProtocols[protocol], "Protocol not approved");
        require(amount > 0, "Amount must be greater than zero");
        
        // Get the ynUSDx token
        IYieldToken ynUSDx = IYieldToken(ynUSDxAddress);
        
        // Transfer ynUSDx from user
        IERC20(ynUSDxAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve the protocol to spend ynUSDx
        IERC20(ynUSDxAddress).approve(protocol, amount);
        
        // Deposit into the yield protocol
        IYieldProtocol yieldProtocol = IYieldProtocol(protocol);
        uint256 sharesMinted = yieldProtocol.deposit(ynUSDxAddress, amount);
        
        // Create stable position
        StablePosition memory stablePosition = StablePosition({
            asset: ynUSDxAddress,
            amount: amount,
            value: _getValueInUSD(ynUSDxAddress, amount),
            yieldProtocol: protocol
        });
        
        // Add to user's portfolio
        userStablePositions[msg.sender][protocol].push(stablePosition);
        
        emit StableDeployed(ynUSDxAddress, amount, protocol);
        
        return true;
    }

    /**
     * @notice Check if portfolio needs rebalancing
     * @return needsRebalance Whether rebalancing is needed
     */
    function needsRebalancing() external view override returns (bool needsRebalance) {
        (
            uint256 totalValue,
            int256 ethExposure,
            int256 btcExposure,
            int256 usdExposure
        ) = getPortfolioSummary();
        
        if (totalValue == 0) return false;
        
        // Calculate current allocations
        uint256 ethAllocation = uint256(ethExposure > int256(0) ? ethExposure : int256(0)) * BASIS_POINTS / totalValue;
        uint256 btcAllocation = uint256(btcExposure > int256(0) ? btcExposure : int256(0)) * BASIS_POINTS / totalValue;
        uint256 usdAllocation = uint256(usdExposure) * BASIS_POINTS / totalValue;
        
        // Check if any allocation deviates from target by more than the threshold
        bool ethDeviation = _absoluteDifference(ethAllocation, targetETHAllocation) > rebalanceThreshold;
        bool btcDeviation = _absoluteDifference(btcAllocation, targetBTCAllocation) > rebalanceThreshold;
        bool usdDeviation = _absoluteDifference(usdAllocation, targetUSDAllocation) > rebalanceThreshold;
        
        return ethDeviation || btcDeviation || usdDeviation;
    }

    /**
     * @notice Rebalance the portfolio to maintain delta neutrality
     * @return success Whether the rebalance was successful
     */
    function rebalance() external override nonReentrant returns (bool success) {
        (
            uint256 totalValue,
            int256 ethExposure,
            int256 btcExposure,
            int256 usdExposure
        ) = getPortfolioSummary();
        
        if (totalValue == 0) return true; // Nothing to rebalance
        
        // Calculate target exposures
        uint256 targetETHValue = totalValue * targetETHAllocation / BASIS_POINTS;
        uint256 targetBTCValue = totalValue * targetBTCAllocation / BASIS_POINTS;
        
        // Calculate required hedge adjustments
        int256 ethAdjustment = int256(targetETHValue) - ethExposure;
        int256 btcAdjustment = int256(targetBTCValue) - btcExposure;
        
        // Adjust ETH hedge positions
        if (ethAdjustment < 0) {
            // Need to increase short position
            uint256 amountToShort = uint256(-ethAdjustment);
            // Convert USD value to ETH amount
            uint256 ethAmount = _convertUSDToAssetAmount(wethAddress, amountToShort);
            
            // Create hedge position
            _createHedgePosition(AssetType.ETH, ethAmount, true);
        } else if (ethAdjustment > 0) {
            // Need to reduce short position
            _reduceHedgePositions(AssetType.ETH, uint256(ethAdjustment));
        }
        
        // Adjust BTC hedge positions
        if (btcAdjustment < 0) {
            // Need to increase short position
            uint256 amountToShort = uint256(-btcAdjustment);
            // Convert USD value to BTC amount
            uint256 btcAmount = _convertUSDToAssetAmount(wbtcAddress, amountToShort);
            
            // Create hedge position
            _createHedgePosition(AssetType.BTC, btcAmount, true);
        } else if (btcAdjustment > 0) {
            // Need to reduce short position
            _reduceHedgePositions(AssetType.BTC, uint256(btcAdjustment));
        }
        
        // Get updated portfolio state
        (
            ,
            int256 newEthExposure,
            int256 newBtcExposure,
            int256 newUsdExposure
        ) = getPortfolioSummary();
        
        emit PortfolioRebalanced(newEthExposure, newBtcExposure, newUsdExposure);
        
        return true;
    }

    /**
     * @notice Calculate estimated APR based on current positions
     * @return apr The estimated APR in basis points (1% = 100 basis points)
     */
    function calculateEstimatedAPR() external view override returns (uint256 apr) {
        (
            uint256 totalValue,
            ,
            ,
            
        ) = getPortfolioSummary();
        
        if (totalValue == 0) return 0;
        
        uint256 totalYield = 0;
        
        // Calculate yield from all yield tokens
        totalYield += _calculateYieldFromToken(ynETHxAddress);
        totalYield += _calculateYieldFromToken(ynBTCxAddress);
        totalYield += _calculateYieldFromToken(ynUSDxAddress);
        
        // Calculate yield from stable positions in protocols
        for (uint256 i = 0; i < userHedgePositions[msg.sender].length; i++) {
            uint256 positionId = userHedgePositions[msg.sender][i];
            HedgePosition storage position = hedgePositions[positionId];
            
            // Hedging costs (typically negative for shorts)
            int256 fundingCost = position.fundingRate * int256(position.value) / int256(1e6);
            
            // Subtract hedging costs from total yield
            if (fundingCost < 0) {
                totalYield = totalYield > uint256(-fundingCost) ? totalYield - uint256(-fundingCost) : 0;
            } else {
                totalYield += uint256(fundingCost);
            }
        }
        
        // Return APR in basis points
        return totalYield * BASIS_POINTS / totalValue;
    }

    /**
     * @notice Get the current portfolio state summary
     * @return totalValue Total portfolio value
     * @return ethExposure Net ETH exposure
     * @return btcExposure Net BTC exposure
     * @return usdExposure Net USD exposure
     */
    function getPortfolioSummary() public view override returns (
        uint256 totalValue,
        int256 ethExposure,
        int256 btcExposure,
        int256 usdExposure
    ) {
        // Calculate ETH exposure
        for (uint256 i = 0; i < userYieldPositions[msg.sender][AssetType.ETH].length; i++) {
            YieldPosition storage position = userYieldPositions[msg.sender][AssetType.ETH][i];
            ethExposure += int256(position.value);
            totalValue += position.value;
        }
        
        // Calculate BTC exposure
        for (uint256 i = 0; i < userYieldPositions[msg.sender][AssetType.BTC].length; i++) {
            YieldPosition storage position = userYieldPositions[msg.sender][AssetType.BTC][i];
            btcExposure += int256(position.value);
            totalValue += position.value;
        }
        
        // Calculate USD exposure
        for (uint256 i = 0; i < userYieldPositions[msg.sender][AssetType.USD].length; i++) {
            YieldPosition storage position = userYieldPositions[msg.sender][AssetType.USD][i];
            usdExposure += int256(position.value);
            totalValue += position.value;
        }
        
        // Add stablecoin positions from protocols
        address[] memory protocols = _getApprovedProtocols();
        for (uint256 i = 0; i < protocols.length; i++) {
            address protocol = protocols[i];
            for (uint256 j = 0; j < userStablePositions[msg.sender][protocol].length; j++) {
                StablePosition storage position = userStablePositions[msg.sender][protocol][j];
                usdExposure += int256(position.value);
                totalValue += position.value;
            }
        }
        
        // Subtract hedge positions
        for (uint256 i = 0; i < userHedgePositions[msg.sender].length; i++) {
            uint256 positionId = userHedgePositions[msg.sender][i];
            HedgePosition storage position = hedgePositions[positionId];
            
            if (position.asset == wethAddress) {
                ethExposure -= int256(position.value);
            } else if (position.asset == wbtcAddress) {
                btcExposure -= int256(position.value);
            }
        }
    }

    /**
     * @notice Add an approved yield protocol
     * @param protocol Address of the yield protocol to approve
     * @return success Whether the protocol was added successfully
     */
    function addYieldProtocol(address protocol) external onlyOwner returns (bool success) {
        require(protocol != address(0), "Invalid protocol address");
        require(!approvedYieldProtocols[protocol], "Protocol already approved");
        
        approvedYieldProtocols[protocol] = true;
        emit YieldProtocolAdded(protocol);
        
        return true;
    }

    /**
     * @notice Remove an approved yield protocol
     * @param protocol Address of the yield protocol to remove
     * @return success Whether the protocol was removed successfully
     */
    function removeYieldProtocol(address protocol) external onlyOwner returns (bool success) {
        require(approvedYieldProtocols[protocol], "Protocol not approved");
        
        approvedYieldProtocols[protocol] = false;
        emit YieldProtocolRemoved(protocol);
        
        return true;
    }

    /**
     * @notice Set the hedging platform address
     * @param platform Address of the hedging platform
     * @return success Whether the platform was set successfully
     */
    function setHedgingPlatform(address platform) external onlyOwner returns (bool success) {
        require(platform != address(0), "Invalid platform address");
        
        hedgingPlatformAddress = platform;
        emit HedgingPlatformSet(platform);
        
        return true;
    }

    /**
     * @notice Update target allocations
     * @param _ethAllocation Target ETH allocation in basis points
     * @param _btcAllocation Target BTC allocation in basis points
     * @param _usdAllocation Target USD allocation in basis points
     * @return success Whether the allocations were updated successfully
     */
    function updateAllocations(
        uint256 _ethAllocation,
        uint256 _btcAllocation,
        uint256 _usdAllocation
    ) external onlyOwner returns (bool success) {
        require(_ethAllocation + _btcAllocation + _usdAllocation == BASIS_POINTS, "Invalid allocations");
        
        targetETHAllocation = _ethAllocation;
        targetBTCAllocation = _btcAllocation;
        targetUSDAllocation = _usdAllocation;
        
        emit AllocationUpdated(_ethAllocation, _btcAllocation, _usdAllocation);
        
        return true;
    }

    /**
     * @notice Helper function to create a hedge position internally
     * @param assetType Type of asset to hedge
     * @param amount Amount to hedge
     * @param isShort Whether the position is short
     * @return positionId ID of the created position
     */
    function _createHedgePosition(AssetType assetType, uint256 amount, bool isShort) internal returns (uint256 positionId) {
        address asset;
        if (assetType == AssetType.ETH) {
            asset = wethAddress;
        } else if (assetType == AssetType.BTC) {
            asset = wbtcAddress;
        } else {
            revert("Cannot hedge USD assets");
        }
        
        // Interact with the hedging platform
        IHedgingPlatform hedgingPlatform = IHedgingPlatform(hedgingPlatformAddress);
        
        // Approve asset for hedging platform
        IERC20(asset).approve(hedgingPlatformAddress, amount);
        
        // Open short position
        (uint256 newPositionId, uint256 executedAmount) = hedgingPlatform.openShortPosition(
            asset,
            amount,
            MAX_SLIPPAGE
        );
        
        // Get position details
        (
            ,
            ,
            ,
            ,
            ,
            int256 fundingRate
        ) = hedgingPlatform.getPositionInfo(newPositionId);
        
        // Create hedge position
        HedgePosition memory hedgePosition = HedgePosition({
            asset: asset,
            amount: executedAmount,
            value: _getValueInUSD(asset, executedAmount),
            isShort: isShort,
            fundingRate: fundingRate
        });
        
        // Store position
        hedgePositions[newPositionId] = hedgePosition;
        userHedgePositions[msg.sender].push(newPositionId);
        nextPositionId++;
        
        emit HedgePositionCreated(asset, executedAmount, isShort);
        
        return newPositionId;
    }

    /**
     * @notice Helper function to reduce hedge positions
     * @param assetType Type of asset to reduce hedging for
     * @param valueToReduce USD value to reduce by
     */
    function _reduceHedgePositions(AssetType assetType, uint256 valueToReduce) internal {
        address targetAsset = assetType == AssetType.ETH ? wethAddress : wbtcAddress;
        
        for (uint256 i = 0; i < userHedgePositions[msg.sender].length && valueToReduce > 0; i++) {
            uint256 positionId = userHedgePositions[msg.sender][i];
            HedgePosition storage position = hedgePositions[positionId];
            
            // Skip if not the target asset or not a short position
            if (position.asset != targetAsset || !position.isShort) continue;
            
            uint256 closeValue = Math.min(position.value, valueToReduce);
            uint256 closeAmount = closeValue * position.amount / position.value;
            
            if (closeAmount > 0) {
                // Interact with hedging platform to close part of the position
                IHedgingPlatform hedgingPlatform = IHedgingPlatform(hedgingPlatformAddress);
                
                // Close position
                (uint256 closedAmount, ) = hedgingPlatform.closeShortPosition(
                    positionId,
                    closeAmount,
                    MAX_SLIPPAGE
                );
                
                // Update position
                position.amount -= closedAmount;
                position.value = _getValueInUSD(position.asset, position.amount);
                
                // Reduce the remaining value to close
                valueToReduce -= closeValue;
                
                // If position fully closed, remove it
                if (position.amount == 0) {
                    // Remove from userHedgePositions
                    for (uint256 j = i; j < userHedgePositions[msg.sender].length - 1; j++) {
                        userHedgePositions[msg.sender][j] = userHedgePositions[msg.sender][j + 1];
                    }
                    userHedgePositions[msg.sender].pop();
                    
                    // Delete position
                    delete hedgePositions[positionId];
                    
                    // Decrement i because we removed an element
                    i--;
                }
            }
        }
    }

    /**
     * @notice Calculate yield from a specific yield token
     * @param tokenAddress Address of the yield token
     * @return yield Annual yield in USD value
     */
    function _calculateYieldFromToken(address tokenAddress) internal view returns (uint256 yield) {
        IYieldToken yieldToken = IYieldToken(tokenAddress);
        uint256 apr = yieldToken.currentAPR();
        
        AssetType assetType;
        if (tokenAddress == ynETHxAddress) {
            assetType = AssetType.ETH;
        } else if (tokenAddress == ynBTCxAddress) {
            assetType = AssetType.BTC;
        } else if (tokenAddress == ynUSDxAddress) {
            assetType = AssetType.USD;
        } else {
            return 0;
        }
        
        uint256 totalValue = 0;
        
        // Calculate total value in this token
        for (uint256 i = 0; i < userYieldPositions[msg.sender][assetType].length; i++) {
            if (userYieldPositions[msg.sender][assetType][i].asset == tokenAddress) {
                totalValue += userYieldPositions[msg.sender][assetType][i].value;
            }
        }
        
        // Calculate annual yield
        return totalValue * apr / BASIS_POINTS;
    }

    /**
     * @notice Get the value of a token amount in USD
     * @param tokenAddress Address of the token
     * @param amount Amount of the token
     * @return usdValue USD value of the token amount
     */
    function _getValueInUSD(address tokenAddress, uint256 amount) internal view returns (uint256 usdValue) {
        // In a real implementation, this would use an oracle
        
        if (tokenAddress == ynETHxAddress || tokenAddress == wethAddress) {
            // Assuming 1 ETH = $3,000 USD
            return (amount * 3000e18) / 1e18;
        } else if (tokenAddress == ynBTCxAddress || tokenAddress == wbtcAddress) {
            // Assuming 1 BTC = $50,000 USD
            return (amount * 50000e18) / 1e8;
        } else if (tokenAddress == ynUSDxAddress) {
            // Stablecoins are 1:1 with USD
            return amount;
        }
        
        return 0;
    }

    /**
     * @notice Convert USD value to asset amount
     * @param assetAddress Address of the asset
     * @param usdValue USD value to convert
     * @return assetAmount Amount of the asset
     */
    function _convertUSDToAssetAmount(address assetAddress, uint256 usdValue) internal view returns (uint256 assetAmount) {
        if (assetAddress == wethAddress) {
            // Assuming 1 ETH = $3,000 USD
            return (usdValue * 1e18) / 3000e18;
        } else if (assetAddress == wbtcAddress) {
            // Assuming 1 BTC = $50,000 USD
            return (usdValue * 1e8) / 50000e18;
        } else if (assetAddress == ynUSDxAddress) {
            // Stablecoins are 1:1 with USD
            return usdValue;
        }
        
        return 0;
    }

    /**
     * @notice Get the absolute difference between two values
     * @param a First value
     * @param b Second value
     * @return diff Absolute difference
     */
    function _absoluteDifference(uint256 a, uint256 b) internal pure returns (uint256 diff) {
        return a > b ? a - b : b - a;
    }

    /**
     * @notice Get an array of all approved protocols
     * @return protocols Array of approved protocol addresses
     */
    function _getApprovedProtocols() internal view returns (address[] memory protocols) {
        uint256 count = 0;
        
        // First, count the number of approved protocols
        for (uint256 i = 0; i < 100; i++) { // Arbitrary limit
            address potentialProtocol = address(uint160(i));
            if (approvedYieldProtocols[potentialProtocol]) {
                count++;
            }
        }
        
        // Allocate the array
        protocols = new address[](count);
        
        // Fill the array
        uint256 index = 0;
        for (uint256 i = 0; i < 100 && index < count; i++) {
            address potentialProtocol = address(uint160(i));
            if (approvedYieldProtocols[potentialProtocol]) {
                protocols[index] = potentialProtocol;
                index++;
            }
        }
    }
} 