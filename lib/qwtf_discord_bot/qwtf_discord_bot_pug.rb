# frozen_string_literal: true

require 'pug'
require 'event_decorator'

class QwtfDiscordBotPug # :nodoc:
  include QwtfDiscordBot

  MSG_SNIPPET_DELIMITER = ' · '

  def run
    bot = Discordrb::Commands::CommandBot.new(
      token: QwtfDiscordBot.config.token,
      client_id: QwtfDiscordBot.config.client_id,
      help_command: false,
      prefix: '!'
    )

    bot.command :join do |event, *args|
      setup_pug(event) do |e, pug|
        return send_msg("You've already joined", e.channel) if pug.joined?(e.user_id)

        join_pug(e, pug)

        start_pug(pug, e) if pug.full?
      end
    end

    bot.command :status do |event, *args|
      setup_pug(event) do |e, pug|
        msg = if !pug.active?
                'No PUG has been started. `!join` to create'
              else
                [
                  "#{pug.player_slots} joined",
                  pug_teams_message(pug, e).join("\n")
                ].join("\n")
              end

        send_msg(msg, e.channel)
      end
    end

    bot.command :teamsize do |event, *args|
      setup_pug(event) do |e, pug|
        new_teamsize = args[0]

        if new_teamsize
          pug.teamsize = new_teamsize

          send_msg(
            [
              "Team size set to #{pug.teamsize}",
              "#{pug.player_slots} joined"
            ].join(MSG_SNIPPET_DELIMITER),
            e.channel
          )

          start_pug(pug, e) if pug.full?
        else
          send_msg(
            [
              "Current team size is #{pug.teamsize}",
              "#{pug.player_slots} joined"
            ].join(MSG_SNIPPET_DELIMITER),
            e.channel
          )
        end
      end
    end

    bot.command :leave do |event, *args|
      setup_pug(event) do |e, pug|
        return send_msg(no_active_pug_message, e.channel) unless pug.active?
        return send_msg("You're not in the PUG", e.channel) unless pug.joined?(e.user_id)

        pug.leave(e.user_id)

        snippets = [
          "#{e.display_name} leaves the PUG",
          "#{pug.player_slots} remain"
        ]

        snippets << "#{pug.slots_left} more #{pug.notify_roles}" if pug.slots_left == 1

        send_msg(
          snippets.join(MSG_SNIPPET_DELIMITER),
          e.channel
        )

        send_msg(end_pug_message, e.channel) unless pug.active?
      end
    end

    bot.command :kick do |event, *args|
      setup_pug(event) do |e, pug|
        return send_msg(no_active_pug_message, e.channel) unless pug.active?

        args.each do |arg|
          unless arg.match(/<@!\d+>/)
            send_msg("#{arg} isn't a valid mention", e.channel)
            next
          end

          user_id = arg[3..-2].to_i
          display_name = e.display_name_for(user_id) || arg

          unless pug.joined?(user_id)
            send_msg("#{display_name} isn't in the PUG", e.channel)
            next
          end

          pug.leave(user_id)

          snippets = [
            "#{display_name} is kicked from the PUG",
            "#{pug.player_slots} remain"
          ]

          snippets << "#{pug.slots_left} more #{pug.notify_roles}" if pug.slots_left == 1

          send_msg(
            snippets.join(MSG_SNIPPET_DELIMITER),
            e.channel
          )

          break send_msg(end_pug_message, e.channel) unless pug.active?
        end
      end
    end

    bot.command :team do |event, *args|
      setup_pug(event) do |e, pug|
        team_no = args[0].to_i

        user_id = e.user_id

        return send_msg("You're already in team #{team_no}", e.channel) if pug.team(team_no).include?(user_id)

        join_pug(e, pug) unless pug.joined?(user_id)

        pug.join_team(team_no: team_no, player_id: user_id)

        snippets = if team_no.zero?
                     ["#{e.display_name} has no team"]
                   else
                     [
                       "#{e.display_name} joins team #{team_no}",
                       "#{pug.team_player_count(team_no)}/#{pug.teamsize}"
                     ]
                   end

        send_msg(snippets.join(MSG_SNIPPET_DELIMITER), e.channel)

        start_pug(pug, e) if pug.full?
      end
    end

    # bot.command :win do |event, *args|
    #   setup_pug(event) do |e, pug|
    #     return send_msg(no_active_pug_message, e.channel) unless pug.active?

    #     team_no = arg[0]

    #     pug.won_by = team_no

    #     send_msg("Team #{team_no} has been declared winner", e.channel)
    #   end
    # end


    bot.command :end do |event, *args|
      setup_pug(event) do |e, pug|
        return send_msg(no_active_pug_message, e.channel) unless pug.active?

        pug.end_pug

        send_msg(end_pug_message, e.channel)
      end
    end

    bot.command :notify do |event, *args|
      setup_pug(event) do |e, pug|
        roles = args.join(' ')
        pug.notify_roles = roles

        msg = if roles.empty?
                'Notification removed'
              else
                "Notification role set to #{roles}"
              end

        send_msg(msg, e.channel)
      end
    end

    bot.run
  end

  private

  def join_pug(e, pug)
    pug.join(e.user_id)

    if pug.joined_player_count == 1
      snippets = ["#{e.display_name} creates a PUG", pug.player_slots, pug.notify_roles]
    else
      snippets = ["#{e.display_name} joins the PUG", pug.player_slots]
      snippets << "#{pug.slots_left} more #{pug.notify_roles}" if pug.slots_left.between?(1, 3)
    end

    send_msg(snippets.join(MSG_SNIPPET_DELIMITER), e.channel)
  end

  def setup_pug(event)
    e = EventDecorator.new(event)
    pug = Pug.for(e.channel_id)
    yield(e, pug)
    nil # stop discordrb printing return value
  end

  def start_pug(pug, event)
    pug_teams = pug.teams.map do |team_no, player_ids|
      team_mentions = player_ids.map do |player_id|
        event.mention_for(player_id)
      end

      team_status_line(
        team_no: team_no.to_i,
        names: team_mentions,
        teamsize: pug.teamsize
      )
    end

    msg = [
      'Time to play!',
      pug_teams
    ].join("\n")

    send_msg(msg, event.channel)
  end

  def pug_teams_message(pug, event)
    pug.teams.map do |team_no, player_ids|
      team_display_names = player_ids.map do |player_id|
        event.display_name_for(player_id)
      end

      team_status_line(
        team_no: team_no.to_i,
        names: team_display_names,
        teamsize: pug.teamsize
      )
    end
  end

  def team_status_line(team_no:, names:, teamsize:)
    if team_no.to_i.zero?
      ["No team: #{names.join(', ')}"]
    else
      [
        "Team #{team_no}: #{names.join(', ')}",
        "#{names.count}/#{teamsize}"
      ].join(MSG_SNIPPET_DELIMITER)
    end
  end

  def end_pug_message
    'PUG ended'
  end

  def no_active_pug_message
    "There's no active PUG"
  end

  def send_msg(message, channel)
    channel.send_message(message) && puts(message)
  end
end
