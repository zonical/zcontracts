SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

--
-- Database: `zcontracts`
--
CREATE DATABASE IF NOT EXISTS `zcontracts` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `zcontracts`;

-- --------------------------------------------------------

--
-- Table structure for table `completed_contracts`
--

CREATE TABLE IF NOT EXISTS `completed_contracts` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `completions` tinyint(4) NOT NULL DEFAULT '1',
  `reset` tinyint(1) NOT NULL DEFAULT '0',
  UNIQUE KEY `steamid64` (`steamid64`,`contract_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `contract_progress`
--

CREATE TABLE IF NOT EXISTS `contract_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `progress` int(11) NOT NULL DEFAULT '0',
  `version` tinyint(4) NOT NULL,
  UNIQUE KEY `steamid64` (`steamid64`,`contract_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `objective_progress`
--

CREATE TABLE IF NOT EXISTS `objective_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `objective_id` int(11) DEFAULT NULL,
  `progress` int(11) DEFAULT '0',
  `version` tinyint(4) NOT NULL,
  UNIQUE KEY `objective_key` (`steamid64`,`contract_uuid`,`objective_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `preferences`
--

CREATE TABLE IF NOT EXISTS `preferences` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` tinyint(4) NOT NULL,
  `display_help_text` tinyint(1) NOT NULL DEFAULT '1',
  `use_contract_hud` tinyint(1) NOT NULL DEFAULT '1',
  `use_hint_text` tinyint(11) NOT NULL DEFAULT '1',
  `use_sounds` tinyint(11) NOT NULL DEFAULT '1',
  `display_hud_repeat` tinyint(4) NOT NULL DEFAULT '1',
  `open_status` tinyint(4) NOT NULL DEFAULT '1',
  PRIMARY KEY (`steamid64`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `selected_contract`
--

CREATE TABLE IF NOT EXISTS `selected_contract` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  UNIQUE KEY `steamid64` (`steamid64`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
COMMIT;
