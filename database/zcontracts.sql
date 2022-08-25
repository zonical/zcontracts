SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

CREATE DATABASE IF NOT EXISTS `zcontracts` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `zcontracts`;

CREATE TABLE `contract_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `progress` int(11) NOT NULL,
  `complete` bit(1) NOT NULL DEFAULT b'0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `objective_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `objective_id` int(11) DEFAULT NULL,
  `progress` int(11) DEFAULT NULL,
  `fires` int(11) DEFAULT NULL,
  `complete` bit(1) NOT NULL DEFAULT b'0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `selected_contract` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
