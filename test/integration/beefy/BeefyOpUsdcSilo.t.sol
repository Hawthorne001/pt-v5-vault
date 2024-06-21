// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseIntegration, IERC20, IERC4626 } from "../BaseIntegration.t.sol";

contract BeefyOpUsdcSiloIntegrationTest is BaseIntegration {
    uint256 fork;
    uint256 forkBlock = 121697613;
    uint256 forkBlockTimestamp = 1718994003;

    address internal _beefyWrapper = address(0x182be93E1C0C4d305fe43bD093292F21fd679797);

    address internal _asset = address(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
    address internal _assetWhale = address(0xcE8CcA271Ebc0533920C83d39F417ED6A0abB7D0);
    address internal _yieldVault;
    address internal _mooVault = address(0xEE2e18164609499cd623E493307B1e5a68fccC5B);
    address internal _mooYieldSource = address(0x6f7c5CD510B325EdB65C48DcF4E9416EF9C5a1BC);
    address internal _siloYieldToken = address(0x96000e67d7372DEEDEBbD4c9558Bd97935F7cEA5);

    /* ============ setup ============ */

    function setUpUnderlyingAsset() public virtual override returns (IERC20 asset, uint8 decimals, uint256 approxAssetUsdExchangeRate) {
        return (IERC20(_asset), 6, 1e18);
    }

    function setUpYieldVault() public virtual override returns (IERC4626) {
        (bool success, bytes memory data) = _beefyWrapper.call(abi.encodeWithSignature("clone(address)", _mooVault));
        require(success, "beefy vault wrapper failed");
        (_yieldVault) = abi.decode(data, (address));
        return IERC4626(_yieldVault);
    }

    function setUpFork() public virtual override {
        fork = vm.createFork(vm.rpcUrl("optimism"), forkBlock);
        vm.selectFork(fork);
        vm.warp(forkBlockTimestamp);
    }

    function beforeSetup() public virtual override {
        lowGasPriceEstimate = 0.05 gwei; // just L2 gas, we ignore L1 costs for a super low estimate
        assetPrecisionLoss = 1; // loses 1 decimal of precision due to Silo rounding errors
    }

    function afterSetup() public virtual override { }

    /* ============ helpers to override ============ */

    /// @dev The max amount of assets than can be dealt.
    function maxDeal() public virtual override returns (uint256) {
        return underlyingAsset.balanceOf(_assetWhale);
    }

    /// @dev May revert if the amount requested exceeds the amount available to deal.
    function dealAssets(address to, uint256 amount) public virtual override prankception(_assetWhale) {
        underlyingAsset.transfer(to, amount);
    }

    /// @dev Accrues yield by letting time pass and triggering multiple yield accruals
    function _accrueYield() internal virtual override prankception(_assetWhale) {
        // yield accrues on deposit / withdraw so we can do a deposit and withdraw to the yield vault directly to trigger some yield accrual
        uint256 amount = 10 ** assetDecimals; // some small amount of assets
        underlyingAsset.approve(_yieldVault, amount);
        yieldVault.deposit(amount, _assetWhale);
        vm.warp(block.timestamp + 1 days); // let 1 day pass by
        uint256 maxRedeem = yieldVault.maxRedeem(_assetWhale);
        yieldVault.redeem(maxRedeem, _assetWhale, _assetWhale);

        // we also call a deposit directly on the moo vault to ensure it triggers a yield accrual
        underlyingAsset.approve(_mooVault, amount);
        (bool success,) = _mooVault.call(abi.encodeWithSignature("deposit(uint256)", amount));
        assertEq(success, true, "moo vault deposit success");
    }

    /// @dev Simulates loss by sending yield-bearing tokens out of the yield source and re-depositing some assets to trigger an update
    function _simulateLoss() internal virtual override prankception(_mooYieldSource) {
        IERC20(_siloYieldToken).transfer(_assetWhale, IERC20(_siloYieldToken).balanceOf(_mooYieldSource) / 2);
        startPrank(alice);
        uint256 amount = 10 ** assetDecimals;
        dealAssets(alice, amount);
        underlyingAsset.approve(_yieldVault, amount);
        yieldVault.deposit(amount, alice);
        stopPrank();
    }

}