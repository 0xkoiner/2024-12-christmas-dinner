//SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {Test, console, console2} from "forge-std/Test.sol";
import {ChristmasDinner} from "../src/ChristmasDinner.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Attack} from "src/Attack.sol";

contract ChristmasDinnerTest is Test {
    event NewHost(address indexed);

    ChristmasDinner cd;
    Attack ac;

    ERC20Mock wbtc;
    ERC20Mock weth;
    ERC20Mock usdc;

    uint256 constant DEADLINE = 1;
    address deployer = makeAddr("deployer");
    address user1;
    address user2;
    address user3;
    address OWNER = makeAddr("OWNER");

    function setUp() public {
        wbtc = new ERC20Mock();
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        vm.startPrank(deployer);
        cd = new ChristmasDinner(address(wbtc), address(weth), address(usdc));
        ac = new Attack(
            address(wbtc),
            address(weth),
            address(usdc),
            OWNER,
            payable(address(cd))
        );
        vm.warp(1);
        cd.setDeadline(DEADLINE);
        vm.stopPrank();
        _makeParticipants();
    }

    ////////////////////////////////////////////////////////////////
    //////////////////    Deadline Shenenigans     /////////////////
    ////////////////////////////////////////////////////////////////

    // Try resetting Deadline
    function test_tryResettingDeadlineAsHost() public {
        vm.startPrank(deployer);
        cd.setDeadline(8 days);
        vm.stopPrank();
    }

    function test_settingDeadlineAsUser() public {
        vm.startPrank(user1);
        vm.expectRevert();
        cd.setDeadline(3);
        vm.stopPrank();
    }

    // Refund Scenarios
    function test_refundAfterDeadline() public {
        uint256 depositAmount = 1e18;
        vm.startPrank(user1);
        cd.deposit(address(wbtc), depositAmount);
        assertEq(wbtc.balanceOf(address(cd)), depositAmount);
        vm.warp(1 + 8 days);
        vm.expectRevert();
        cd.refund();
        vm.stopPrank();
        assertEq(wbtc.balanceOf(address(cd)), depositAmount);
    }

    function test_refundWithinDeadline() public {
        uint256 depositAmount = 1e18;
        uint256 userBalanceBefore = weth.balanceOf(user1);
        vm.startPrank(user1);
        cd.deposit(address(weth), depositAmount);
        assertEq(weth.balanceOf(address(cd)), depositAmount);
        assertEq(weth.balanceOf(user1), userBalanceBefore - depositAmount);
        vm.warp(1 + 3 days);
        cd.refund();
        assertEq(weth.balanceOf(address(cd)), 0);
        assertEq(weth.balanceOf(user1), userBalanceBefore);
    }

    function test_refundWithEther() public {
        address payable _cd = payable(address(cd));
        vm.deal(user1, 10e18);
        vm.prank(user1);
        (bool sent, ) = _cd.call{value: 1e18}("");
        require(sent, "transfer failed");
        assertEq(user1.balance, 9e18);
        assertEq(address(cd).balance, 1e18);
        vm.prank(user1);
        cd.refund();
        assertEq(user1.balance, 10e18);
        assertEq(address(cd).balance, 0);
    }

    // Change Participation Status Scenarios
    function test_participationStatusAfterDeadlineToFalse() public {
        vm.startPrank(user1);
        cd.deposit(address(weth), 1e18);
        assertEq(cd.getParticipationStatus(user1), true);
        vm.warp(1 + 8 days);
        cd.changeParticipationStatus();
        assertEq(cd.getParticipationStatus(user1), false);
    }

    function test_participationStatusAfterDeadlineToTrue() public {
        vm.startPrank(user1);
        cd.deposit(address(weth), 1e18);
        assertEq(cd.getParticipationStatus(user1), true);
        cd.changeParticipationStatus();
        assertEq(cd.getParticipationStatus(user1), false);
        vm.warp(1 + 8 days);
        vm.expectRevert();
        cd.changeParticipationStatus();
        assertEq(cd.getParticipationStatus(user1), false);
    }

    function test_participationStatusBeforeDeadline() public {
        vm.startPrank(user1);
        cd.deposit(address(weth), 1e18);
        assertEq(cd.getParticipationStatus(user1), true);
        cd.changeParticipationStatus();
        assertEq(cd.getParticipationStatus(user1), false);
    }

    // Deposit Scenarios
    function test_depositBeforeDeadline() public {
        vm.warp(1 + 3 days);
        vm.startPrank(user1);
        cd.deposit(address(wbtc), 1e18);
        assertEq(wbtc.balanceOf(user1), 1e18);
        assertEq(wbtc.balanceOf(address(cd)), 1e18);
        vm.stopPrank();
    }

    function test_depositAfterDeadline() public {
        vm.warp(1 + 8 days);
        vm.startPrank(user1);
        vm.expectRevert();
        cd.deposit(address(wbtc), 1e18);
        vm.stopPrank();
    }

    function test_depositNonWhitelistedToken() public {
        ERC20Mock usdt = new ERC20Mock();
        usdt.mint(user1, 1e19);
        vm.startPrank(user1);
        usdt.approve(address(cd), type(uint256).max);
        vm.expectRevert();
        cd.deposit(address(usdt), 1e18);
        vm.stopPrank();
    }

    function test_depositGenerousAdditionalContribution() public {
        vm.startPrank(user1);
        cd.deposit(address(wbtc), 1e18);
        cd.deposit(address(weth), 2e18);
        assertEq(weth.balanceOf(address(cd)), 2e18);
        assertEq(wbtc.balanceOf(address(cd)), 1e18);
    }

    function test_depositEther() public {
        address payable _cd = payable(address(cd));
        vm.deal(user1, 10e18);
        vm.prank(user1);
        (bool sent, ) = _cd.call{value: 1e18}("");
        require(sent, "transfer failed");
        assertEq(user1.balance, 9e18);
        assertEq(address(cd).balance, 1e18);
    }

    ////////////////////////////////////////////////////////////////
    ////////////////// Access Controll Shenenigans /////////////////
    ////////////////////////////////////////////////////////////////

    // Change Host Scenarios
    function test_changeHostFail() public {
        vm.startPrank(user1);
        vm.expectRevert();
        cd.changeHost(user1);
        vm.stopPrank();
    }

    function test_changeHostFailNonParticipant() public {
        vm.startPrank(deployer);
        vm.expectRevert();
        cd.changeHost(user1);
        vm.stopPrank();
    }

    function test_changeHostSuccess() public {
        vm.startPrank(user1);
        cd.deposit(address(wbtc), 1e18);
        vm.stopPrank();
        vm.startPrank(deployer);
        cd.changeHost(user1);
        vm.stopPrank();
        address newHost = cd.getHost();
        assertEq(newHost, user1);
    }

    // Withdraw Scenarios
    function test_withdrawAsNonHost() public {
        vm.startPrank(user2);
        cd.deposit(address(weth), 1e18);
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert();
        cd.withdraw();
        vm.stopPrank();
    }

    function test_withdrawAsHost() public {
        uint256 wethAmount;
        uint256 wbtcAmount;
        uint256 usdcAmount;
        vm.startPrank(user1);
        cd.deposit(address(wbtc), 0.5e18);
        wbtcAmount += 0.5e18;
        cd.deposit(address(weth), 2e18);
        wethAmount += 2e18;
        vm.stopPrank();
        vm.startPrank(user2);
        cd.deposit(address(usdc), 2e18);
        usdcAmount += 2e18;
        cd.deposit(address(wbtc), 1e18);
        wbtcAmount += 1e18;
        vm.stopPrank();
        vm.startPrank(deployer);
        cd.withdraw();
        vm.stopPrank();
        assertEq(wbtc.balanceOf(deployer), wbtcAmount);
        assertEq(weth.balanceOf(deployer), wethAmount);
        assertEq(usdc.balanceOf(deployer), usdcAmount);
    }

    ////////////////////////////////////////////////////////////////
    //////////////////    Internal Helper Elves    /////////////////
    ////////////////////////////////////////////////////////////////

    function _makeParticipants() internal {
        user1 = makeAddr("user1");
        wbtc.mint(user1, 2e18);
        weth.mint(user1, 2e18);
        usdc.mint(user1, 2e18);
        vm.startPrank(user1);
        wbtc.approve(address(cd), 2e18);
        weth.approve(address(cd), 2e18);
        usdc.approve(address(cd), 2e18);
        vm.stopPrank();
        user2 = makeAddr("user2");
        wbtc.mint(user2, 2e18);
        weth.mint(user2, 2e18);
        usdc.mint(user2, 2e18);
        vm.startPrank(user2);
        wbtc.approve(address(cd), 2e18);
        weth.approve(address(cd), 2e18);
        usdc.approve(address(cd), 2e18);
        vm.stopPrank();
        user3 = makeAddr("user3");
        wbtc.mint(user3, 2e18);
        weth.mint(user3, 2e18);
        usdc.mint(user3, 2e18);
        vm.startPrank(user3);
        wbtc.approve(address(cd), 2e18);
        weth.approve(address(cd), 2e18);
        usdc.approve(address(cd), 2e18);
        vm.stopPrank();

        wbtc.mint(address(ac), 5e18);
        weth.mint(address(ac), 5e18);
        usdc.mint(address(ac), 5e18);
    }

    function testCheckHost() public {
        address host = cd.host();
        assertEq(deployer, host);
    }

    function testCheckDeadline() public {
        uint256 deadline = cd.deadline();
        assertEq(DEADLINE * 1 days + 1, deadline);
    }

    function testCheckIndexedEvents() public {
        vm.startPrank(user1);

        // Ensure proper setup, e.g., depositing tokens
        cd.deposit(address(wbtc), 1e18);
        cd.deposit(address(weth), 2e18);

        // Start a new transaction with the deployer
        vm.startPrank(deployer);

        // Expect the `NewHost` event to be emitted with `user1` as an indexed parameter
        vm.expectEmit(true, false, false, false); // Check indexed for the first parameter
        emit NewHost(user1); // Emit the event for testing
        cd.changeHost(user1); // Call the function that emits the event

        vm.stopPrank();
    }

    function testDepositAfterDeadline() public {
        vm.startPrank(user1);
        cd.deposit(address(wbtc), 1e18);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(2 days);
        cd.deposit(address(wbtc), 1e18);
        vm.stopPrank();
    }

    function testAttacker() public {
        console2.log("AC address: ", address(ac));
        // 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264
        // 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264
        vm.deal(address(ac), 2e18);
        vm.startPrank(OWNER);
        uint256 AMOUNT = 1e18;
        ac.doAttack(AMOUNT);
        vm.stopPrank();

        console2.log("CD wbtc: ", cd.balances(address(cd), address(wbtc)));
        console2.log("CD weth: ", cd.balances(address(cd), address(weth)));
        console2.log("CD usdc: ", cd.balances(address(cd), address(usdc)));

        console2.log("AC wbtc: ", cd.balances(address(ac), address(wbtc)));
        console2.log("AC weth: ", cd.balances(address(ac), address(weth)));
        console2.log("AC usdc: ", cd.balances(address(ac), address(usdc)));

        console2.log("wbtc: ", wbtc.balanceOf(address(ac)));
        console2.log("weth: ", weth.balanceOf(address(ac)));
        console2.log("usdc: ", usdc.balanceOf(address(ac)));
    }

    function testAttackReenter() public {
        vm.deal(user1, 5e18);
        vm.deal(user2, 5e18);
        vm.deal(user3, 5e18);
        vm.deal(OWNER, 5e18);
        vm.deal(address(ac), 2e18);

        uint256 depositAmout = 3e18;
        address payable _cd = payable(address(cd));

        uint256 cdETHBalanceBeforeAttack = address(cd).balance;
        console2.log(
            "CD ETH Balance Before Attack: ",
            cdETHBalanceBeforeAttack
        );

        uint256 acETHBalanceBeforeAttack = address(ac).balance;
        console2.log(
            "AC ETH Balance Before Attack: ",
            acETHBalanceBeforeAttack
        );

        vm.startPrank(user1);
        (bool sent1, ) = _cd.call{value: depositAmout}("");
        require(sent1, "transfer failed");
        vm.stopPrank();

        vm.startPrank(user2);
        (bool sent2, ) = _cd.call{value: depositAmout}("");
        require(sent2, "transfer failed");
        vm.stopPrank();

        vm.startPrank(user3);
        (bool sent3, ) = _cd.call{value: depositAmout}("");
        require(sent3, "transfer failed");
        vm.stopPrank();

        uint256 cdETHBalanceBeforeAttackAfterUsersDeposit = address(cd).balance;
        console2.log(
            "CD ETH Balance After Deposits: ",
            cdETHBalanceBeforeAttackAfterUsersDeposit
        );

        assertEq(cdETHBalanceBeforeAttackAfterUsersDeposit, depositAmout * 3);

        vm.startPrank(OWNER);
        ac.doAttack(1e18);
        vm.stopPrank();

        // uint256 cdETHBalanceAfterAttack = address(cd).balance;
        // console2.log("CD ETH Balance After Attack: ", cdETHBalanceAfterAttack);

        // uint256 acETHBalanceAfterAttack = address(ac).balance;
        // console2.log("AC ETH Balance After Attack: ", acETHBalanceAfterAttack);
    }

    function testdepositZeroAmountErc20() public {
        console2.log("ac | wbtc before deposit: ", wbtc.balanceOf(address(ac)));
        console2.log("cd | wbtc before deposit: ", wbtc.balanceOf(address(cd)));

        console2.log("***************************************************");

        console2.log("ac | usdc before deposit: ", usdc.balanceOf(address(ac)));
        console2.log("cd | usdc before deposit: ", usdc.balanceOf(address(cd)));

        console2.log("***************************************************");

        console2.log("ac | weth before deposit: ", weth.balanceOf(address(ac)));
        console2.log("cd | weth before deposit: ", weth.balanceOf(address(cd)));

        console2.log("***************************************************");

        vm.startPrank(OWNER);
        ac.depositAttack(1e18);
        vm.stopPrank();

        console2.log("ac | wbtc after deposit: ", wbtc.balanceOf(address(ac)));
        console2.log("cd | wbtc after deposit: ", wbtc.balanceOf(address(cd)));

        console2.log("***************************************************");

        console2.log("ac | usdc after deposit: ", usdc.balanceOf(address(ac)));
        console2.log("cd | usdc after deposit: ", usdc.balanceOf(address(cd)));

        console2.log("***************************************************");

        console2.log("ac | weth after deposit: ", weth.balanceOf(address(ac)));
        console2.log("cd | weth after deposit: ", weth.balanceOf(address(cd)));
    }

    function testGetHost() public {
        address hostState = cd.host();
        address hostGetter = cd.getHost();

        assertEq(hostState, hostGetter);
    }
}
