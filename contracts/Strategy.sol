// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}

interface ILendingPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
}

interface IWETH10 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 value) external;
}

contract Strategy {
    mapping(address => uint) balances;
    address wethAddress;
    address lendingPoolAddressProvider;
    address daiOracleAddress;
    address ethOracleAddress;
    address daiAddress;

    constructor(
        address _wethaddress,
        address _daiAddress,
        address _ethOracleAddress,
        address _daiOracleAddress,
        address _lendingPoolAddressProvider
    ) {
        wethAddress = _wethaddress;
        daiAddress = _daiAddress;
        lendingPoolAddressProvider = _lendingPoolAddressProvider;
        daiOracleAddress = _daiOracleAddress;
        ethOracleAddress = _ethOracleAddress;
    }

    //let users to deposit eth here and call deposit to aave
    function depositETH() public payable {
        require(msg.value > 0, "can't be zero");
        IWETH10 wethContract = IWETH10(wethAddress);
        wethContract.deposit{value: msg.value}();
        //needs to be approved first
        //depositWethBorrowDai(msg.value);
        balances[msg.sender] += msg.value;
    }

    function depositWeth(uint _value) public {
        uint value = _value;
        address lendingPoolAddress = getLendingPool();
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        IERC20 wethContract = IERC20(wethAddress);
        wethContract.approve(lendingPoolAddress, value);
        lendingPool.deposit(wethAddress, value, address(this), 0);
    }

    function borrowDai(uint _value) public {
        uint value = _value;
        address lendingPoolAddress = getLendingPool();
        uint usdAmountDeposited = ((getOraclePrice(ethOracleAddress) *
            10 ** 10) * value) / 10 ** 18;
        uint daiExchangeRate = getOraclePrice(daiOracleAddress);
        uint toBorrow = (usdAmountDeposited /
            (daiExchangeRate * 10 ** 10) /
            2) * 10 ** 18;
        ILendingPool(lendingPoolAddress).borrow(
            daiAddress,
            toBorrow,
            2,
            0,
            address(this)
        );
    }

    function getOraclePrice(
        address _oracleContract
    ) internal view returns (uint) {
        int priceInt;
        (, priceInt, , , ) = AggregatorV3Interface(_oracleContract)
            .latestRoundData();
        uint price = uint(priceInt);
        return price;
    }

    function getLendingPool() public view returns (address) {
        address lendingPoolAddress = ILendingPoolAddressesProvider(
            lendingPoolAddressProvider
        ).getLendingPool();
        return (lendingPoolAddress);
    }

    function getWethBalance() public view returns (uint) {
        uint wethBalance = IERC20(wethAddress).balanceOf(address(this));
        return wethBalance;
    }
}
