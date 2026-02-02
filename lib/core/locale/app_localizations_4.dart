const Map<String, Map<String, String>> appLocalizationsPart4 = {
  'en': {
    'common_add': 'Add',
    'common_you': 'You',
    'common_yes': 'Yes',
    'common_no': 'No',
    'common_none': '(none)',

    'add_teams_appbar_title_prefix': 'Add Teams',
    'add_teams_header_title': 'Add players (by UserId)',

    'add_teams_format_classic': 'Classic',
    'add_teams_format_ucl_group': 'UCL Group',
    'add_teams_format_ucl_swiss': 'UCL Swiss',

    'add_teams_unlock_group': 'Save anytime. Fixtures unlock at exactly 16 or 32 teams.',
    'add_teams_unlock_swiss': 'Save anytime. Fixtures unlock at exactly 18 or 36 teams.',
    'add_teams_unlock_classic': 'Save anytime. Fixtures unlock at 2+ teams.',

    'add_teams_league_pool': 'League Pool',
    'add_teams_unassigned': 'Unassigned',

    'add_teams_group_a': 'Group A',
    'add_teams_group_b': 'Group B',
    'add_teams_group_c': 'Group C',
    'add_teams_group_d': 'Group D',
    'add_teams_group_e': 'Group E',
    'add_teams_group_f': 'Group F',
    'add_teams_group_g': 'Group G',
    'add_teams_group_h': 'Group H',

    'add_teams_max_teams_error_prefix': 'Maximum',
    'add_teams_max_teams_error_suffix': 'teams allowed for this format.',
    'add_teams_user_already_added': 'This user is already added to this league.',

    'add_teams_add_players_title': 'Add players',
    'add_teams_saved_prefix': 'Saved: ',
    'add_teams_new_prefix': 'New: ',

    'add_teams_add_one_player': 'Add one player',
    'add_teams_paste_list': 'Paste a list',
    'add_teams_import_csv': 'Import CSV roster',

    'add_teams_add_player_by_userid_title': 'Add player by UserId',
    'add_teams_userid_hint': 'eS44e35f  (or Firebase uid)',
    'add_teams_lookup_tooltip': 'Lookup',
    'add_teams_resolved_profile_title': 'Resolved profile',
    'add_teams_uid_prefix': 'uid: ',
    'add_teams_will_be_placed_in_prefix': 'Will be placed in: ',
    'add_teams_no_profile_found_help':
        'No profile found for this UserId. Ask the player to login once and share their UserId (eSxxxxxx).',
    'add_teams_lookup_failed_prefix': 'Lookup failed:',

    'add_teams_paste_userids_title': 'Paste UserIds',
    'add_teams_paste_userids_subtitle':
        'Paste one per line (or comma-separated). Use short UserId (eSxxxxxx) or Firebase uid.',
    'add_teams_paste_hint': 'eS44e35f\neS91a2b3\nuid_3',
    'add_teams_paste_at_least_one_userid': 'Paste at least one UserId.',
    'add_teams_validation_failed_prefix': 'Validation failed:',

    'add_teams_clear': 'Clear',
    'add_teams_validate': 'Validate',
    'add_teams_bulk_ok_prefix': 'OK: ',
    'add_teams_bulk_not_found_prefix': 'Not found: ',
    'add_teams_no_profile_found_short': 'No profile found',
    'add_teams_add_valid': 'Add valid',

    'add_teams_saved_toast': 'Teams saved.',

    'add_teams_cannot_generate_group_prefix':
        'Cannot generate fixtures: UCL Group requires exactly 16 or 32 teams. Current: ',
    'add_teams_cannot_generate_swiss_prefix':
        'Cannot generate fixtures: Swiss requires exactly 18 or 36 teams. Current: ',
    'add_teams_cannot_generate_classic_prefix':
        'Cannot generate fixtures: Classic requires at least 2 teams. Current: ',

    'add_teams_swiss_fixtures_already_exist':
        'Swiss fixtures already exist. Generate later rounds from the Swiss round generator.',

    'add_teams_regenerate_fixtures_title': 'Regenerate fixtures?',
    'add_teams_regenerate_fixtures_message':
        'Fixtures already exist. Regenerating will reset all match results.\n\nContinue?',
    'add_teams_regenerate': 'Regenerate',

    'add_teams_invalid_group_structure_prefix': 'Invalid group structure. For',
    'add_teams_invalid_group_structure_suffix': 'teams you must have groups of 4 with correct group names.',

    'add_teams_failed_generate_fixtures': 'Failed to generate fixtures.',
    'add_teams_fixtures_generated_prefix': 'Fixtures generated (',
    'add_teams_fixtures_generated_suffix': ' matches).',

    'add_teams_current_group': 'Current group',
    'add_teams_review_teams': 'Review teams',
    'add_teams_empty_state':
        'No teams yet.\nTap "Add one player", "Paste a list", or "Import CSV roster".',

    'add_teams_label_saved': 'Saved',
    'add_teams_label_new': 'New',

    'add_teams_save_teams': 'Save teams',
    'add_teams_generate_fixtures': 'Generate fixtures',

    'add_teams_team_details_title': 'Team details',
    'add_teams_team_name_label': 'Team name',
    'add_teams_uid_internal_label': 'uid (internal)',
    'add_teams_group_label': 'Group',
    'add_teams_save_changes': 'Save changes',
    'add_teams_remove_team': 'Remove team',

    'league_space_appbar_title': 'League Space',
    'league_space_default_title': 'League Space',
    'league_space_live_badge': 'LIVE',
    'league_space_ended_badge': 'ENDED',
    'league_space_host_prefix': 'Host: ',

    'league_space_failed_to_parse_space_prefix': 'Failed to parse space:',
    'league_space_stream_error_prefix': 'Space stream error:',
    'league_space_audio_connect_failed_prefix': 'Audio connect failed:',

    'league_space_no_active_space': 'No active space right now.\nAsk the organizer to start one.',

    'league_space_join_audio': 'Join Audio',
    'league_space_leave_audio': 'Leave Audio',

    'league_space_mic_on': 'Mic ON',
    'league_space_mic_off': 'Mic OFF',

    'league_space_connected_as_host': 'Connected as host',
    'league_space_connected_as_speaker': 'Connected as speaker',
    'league_space_connected_as_speaker_muted_by_host': 'Connected as speaker (muted by host)',
    'league_space_connected_as_listener': 'Connected as listener (mic muted)',
    'league_space_not_connected': 'Not connected to audio',

    'league_space_space_not_live': 'Space is not live.',
    'league_space_request_sent': 'Request sent.',
    'league_space_request_failed_prefix': 'Request failed:',
    'league_space_request_removed': 'Request removed.',
    'league_space_failed_prefix': 'Failed:',

    'league_space_mic_not_primed_toast':
        'Mic not primed (permission denied). Leave/rejoin after granting mic permission.',
    'league_space_mic_unavailable_permission_denied':
        'Mic unavailable (permission denied on join). Leave/rejoin after granting mic permission.',
    'league_space_mic_unavailable': 'Mic unavailable.',
    'league_space_you_are_muted_by_host': 'You are muted by the host.',
    'league_space_request_to_speak_to_enable_mic': 'Request to speak to enable your mic.',

    'league_space_you_are_speaker': 'You are a speaker',
    'league_space_request_pending': 'Request Pending',
    'league_space_request_to_speak': 'Request to Speak',
    'league_space_request_denied': 'Request denied.',

    'league_space_toast_now_speaker': 'You are now a speaker.',
    'league_space_toast_now_listener': 'You are now a listener.',
    'league_space_toast_host_muted_you': 'Host muted you.',
    'league_space_toast_host_unmuted_you': 'Host unmuted you.',

    'league_space_host_panel_title': 'Host Panel',

    'league_space_requests_title': 'Requests',
    'league_space_requests_error_prefix': 'Requests error:',
    'league_space_no_pending_requests': 'No pending requests.',

    'league_space_uid_prefix': 'uid: ',
    'league_space_wants_to_speak_suffix': '• wants to speak',

    'league_space_deny': 'Deny',
    'league_space_approve': 'Approve',
    'league_space_deny_failed_prefix': 'Deny failed:',
    'league_space_approve_failed_prefix': 'Approve failed:',

    'league_space_approved_prefix': 'Approved ',
    'league_space_denied_prefix': 'Denied ',
    'league_space_removed_speaker_prefix': 'Removed speaker ',
    'league_space_muted_prefix': 'Muted ',
    'league_space_unmuted_prefix': 'Unmuted ',

    'league_space_speakers_title': 'Speakers',
    'league_space_speakers_error_prefix': 'Speakers error:',
    'league_space_no_speakers_yet': 'No speakers yet.',

    'league_space_muted': 'Muted',
    'league_space_unmuted': 'Unmuted',

    'league_space_mute': 'Mute',
    'league_space_unmute': 'Unmute',
    'league_space_remove': 'Remove',

    'league_space_mute_failed_prefix': 'Mute failed:',
    'league_space_remove_failed_prefix': 'Remove failed:',

    'league_create_wizard_step_basics': 'Basics',
    'league_create_wizard_step_rules': 'Rules',
    'league_create_wizard_step_review': 'Review',
    'league_create_wizard_tournament_format_label': 'Tournament format',
    'league_create_wizard_double_rr_label': 'Double RR',
    'league_create_wizard_double_round_robin_title': 'Double Round Robin',
    'league_create_wizard_double_round_robin_subtitle': 'Home & Away legs (if applicable)',
    'league_create_wizard_description_label': 'Description',

    'league_access_charges_required_title': 'App Charges Required',
    'league_access_amount_prefix': 'Amount:',
    'league_access_charges_explanation':
        'To view Fixtures and Standings for Series/Group leagues, participants must pay app charges.',
    'league_access_league_prefix': 'League:',
    'league_access_receipt_prefix': 'Receipt:',
    'league_access_pay_charges': 'Pay Charges',
    'league_access_note_classic_free': 'Classic leagues are free. League creators always have full access.',
    'league_access_charges_paid_success': 'Charges paid successfully',
    'league_access_payment_failed_prefix': 'Payment failed:',

    'league_creation_payment_appbar_title': 'League Creation Charges',
    'league_creation_payment_required_title': 'Payment Required',
    'league_creation_payment_amount_prefix': 'Amount:',
    'league_creation_payment_explanation_prefix':
        'To create this Series/Group league, you must pay app charges.\n\nLeague:',
    'league_creation_payment_provider_prefix': 'Provider:',
    'league_creation_payment_failed_prefix': 'Payment failed:',
    'league_creation_payment_pay_continue': 'Pay & Continue',
  },
};
