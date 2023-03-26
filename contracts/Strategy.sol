// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ILendingPool {
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

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

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}

interface UniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface IWETH10 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 value) external;
}

contract Strategy is Ownable {
    mapping(address => uint) balances;
    address wethAddress;
    address lendingPoolAddressProvider;
    address daiOracleAddress;
    address ethOracleAddress;
    address daiAddress;
    address uniV2RouterAddress;
    address uniV2Factory;
    address daiDebt;

    event ProvidedETHLiquidity(uint token, uint eth, uint LPtokens);
    event WithdrawETHLiquidity(uint amountToken, uint amountETH);

    constructor(
        address _wethaddress,
        address _daiAddress,
        address _ethOracleAddress,
        address _daiOracleAddress,
        address _lendingPoolAddressProvider,
        address _daiDebt
    ) {
        wethAddress = _wethaddress;
        daiAddress = _daiAddress;
        lendingPoolAddressProvider = _lendingPoolAddressProvider;
        daiOracleAddress = _daiOracleAddress;
        ethOracleAddress = _ethOracleAddress;
        uniV2RouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        uniV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        daiDebt = _daiDebt;
    }

    receive() external payable {}

    //let users to deposit eth here and call deposit to aave
    function depositETH() public payable {
        require(msg.value > 0, "can't be zero");
        uint _value = (msg.value * 2) / 3;
        IWETH10 wethContract = IWETH10(wethAddress);
        wethContract.deposit{value: _value}();
        balances[msg.sender] += msg.value;
    }

    function depositWeth() public onlyOwner {
        address lendingPoolAddress = getLendingPool();
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        IERC20 wethContract = IERC20(wethAddress);
        uint value = wethContract.balanceOf(address(this));
        wethContract.approve(lendingPoolAddress, value);
        lendingPool.deposit(wethAddress, value, address(this), 0);
        borrowDai(value);
    }

    function borrowDai(uint _value) internal {
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
        provideLiquidity(value, toBorrow);
    }

    function provideLiquidity(
        uint _valueETH,
        uint _valueDAI
    ) internal returns (uint amountToken, uint amountETH, uint liquidity) {
        uint valueETH = _valueETH / 2;
        uint valueDAI = _valueDAI;
        UniswapV2Router02 uniV2router = UniswapV2Router02(uniV2RouterAddress);
        IERC20 daiContract = IERC20(daiAddress);
        daiContract.approve(uniV2RouterAddress, valueDAI);
        (amountToken, amountETH, liquidity) = uniV2router.addLiquidityETH{
            value: valueETH
        }(
            daiAddress,
            valueDAI,
            (valueDAI * 95) / 100,
            (valueETH * 95) / 100,
            address(this),
            block.timestamp + 1 hours
        );

        emit ProvidedETHLiquidity(amountToken, amountETH, liquidity);
    }

    function withdrawFromUni() public onlyOwner {
        address pair = IUniswapV2Factory(uniV2Factory).getPair(
            wethAddress,
            daiAddress
        );
        uint LPtokenAmt = IERC20(pair).balanceOf(address(this));
        UniswapV2Router02 uniV2Router = UniswapV2Router02(uniV2RouterAddress);
        IERC20(pair).approve(address(uniV2Router), LPtokenAmt);
        (uint amountToken, uint amountETH) = uniV2Router.removeLiquidity(
            daiAddress,
            wethAddress,
            LPtokenAmt,
            1,
            1,
            address(this),
            block.timestamp + 1 minutes
        );

        emit WithdrawETHLiquidity(amountToken, amountETH);
        repayAave();
    }

    function repayAave() internal {
        // find the debt
        IERC20 aaveDebtToken = IERC20(daiDebt);
        IERC20 daiToken = IERC20(daiAddress);
        IWETH10 wethToken = IWETH10(wethAddress);
        address lendingPool = getLendingPool();
        ILendingPool lending_pool = ILendingPool(lendingPool);
        uint debt = aaveDebtToken.balanceOf(address(this));
        uint balance = daiToken.balanceOf(address(this));
        if (debt > balance) {
            swapToDAI(debt - balance);
            balance = daiToken.balanceOf(address(this));
        }
        require(balance >= debt, "Not enought DAI to repay debt");
        daiToken.approve(address(lending_pool), balance);
        lending_pool.repay(daiAddress, balance, 2, address(this));
        debt = aaveDebtToken.balanceOf(address(this));
        require(debt == 0, "debt is not repaid succesfully");
        lending_pool.withdraw(wethAddress, type(uint256).max, address(this));
        wethToken.withdraw(wethToken.balanceOf(address(this)));
    }

    function swapToDAI(uint _amount) internal {
        uint amount = _amount;
        IERC20 wethContract = IERC20(wethAddress);

        UniswapV2Router02 univ2Router = UniswapV2Router02(uniV2RouterAddress);
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = daiAddress;
        uint[] memory result = univ2Router.getAmountsIn(amount, path);

        uint requiredWeth = result[0];
        uint balance = wethContract.balanceOf(address(this));
        require(balance >= requiredWeth, "Insufficient WETH balance");

        bool approved = wethContract.approve(uniV2RouterAddress, balance);
        require(approved, "WETH approval failed");

        univ2Router.swapTokensForExactTokens(
            amount,
            (result[0] * 101) / 100,
            path,
            address(this),
            block.timestamp
        );
    }

    function withdrawAll() public onlyOwner {
        uint amount = address(this).balance;
        payable(msg.sender).transfer(amount);
    }

    function getOraclePrice(
        address _oracleContract
    ) public view returns (uint) {
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
}
