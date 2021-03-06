module TtQueryHelper
  extend ActiveSupport::Concern

  included do
    class_eval do
    scope :visible, lambda { |*args|
      user = args.shift || User.current
      base = Project.allowed_to_condition(user, @visibile_permission, *args)
      scope = includes(:project).where("#{table_name}.project_id IS NULL OR (#{base})")

      if user.admin?
        scope.where("#{table_name}.visibility <> ? OR #{table_name}.user_id = ?", Query::VISIBILITY_PRIVATE, user.id)
      elsif user.memberships.any?
        scope.where(%{#{table_name}.visibility = ?
                       OR (#{table_name}.visibility = ? AND #{table_name}.id IN (
                        SELECT DISTINCT q.id FROM #{table_name} q
                         INNER JOIN #{table_name_prefix}queries_roles#{table_name_suffix} qr on qr.query_id = q.id
                         INNER JOIN #{MemberRole.table_name} mr ON mr.role_id = qr.role_id
                         INNER JOIN #{Member.table_name} m ON m.id = mr.member_id AND m.user_id = ?
                         WHERE q.project_id IS NULL OR q.project_id = m.project_id))
                       OR #{table_name}.user_id = ?},
                    Query::VISIBILITY_PUBLIC, Query::VISIBILITY_ROLES, user.id, user.id)
      elsif user.logged?
        scope.where("#{table_name}.visibility = ? OR #{table_name}.user_id = ?", Query::VISIBILITY_PUBLIC, user.id)
      else
        scope.where("#{table_name}.visibility = ?", Query::VISIBILITY_PUBLIC)
      end
    }
  end
  end
  
  
  # Returns true if the query is visible to +user+ or the current user.
  def visible?(user=User.current)
    return true if user.admin?
    return false unless project.nil? || user.allowed_to?(@visible_permission, project)
    case visibility
      when Query::VISIBILITY_PUBLIC
        true
      when Query::VISIBILITY_ROLES
        if project
          (user.roles_for_project(project) & roles).any?
        else
          Member.where(:user_id => user.id).joins(:roles).where(:member_roles => {:role_id => roles.map(&:id)}).any?
        end
      else
        user == self.user
    end
  end

  def is_private?
    visibility == Query::VISIBILITY_PRIVATE
  end

  def is_public?
    !is_private?
  end
  
  def sql_for_tt_booking_start_date_field(field, operator, value)
    case operator
      when "="
        "DATE(#{self.queried_class.table_name}.started_on) = '#{Time.parse(value[0]).to_date}'"
      when "><"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{Time.parse(value[0]).to_date}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{Time.parse(value[1]).to_date}'"
      when "<="
        "DATE(#{self.queried_class.table_name}.started_on) <= '#{Time.parse(value[0]).to_date}'"
      when ">="
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{Time.parse(value[0]).to_date}'"  
      when "><t+"
        "DATE(#{self.queried_class.table_name}.started_on) <= '#{(Time.now.localtime+value[0].to_i.days).to_date}' AND DATE(#{self.queried_class.table_name}.started_on) > '#{Time.now.localtime.to_date}'"
      when "><t-"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{(Time.now.localtime-value[0].to_i.days).to_date}' AND DATE(#{self.queried_class.table_name}.started_on) < '#{Time.now.localtime.to_date}'"
      when "t"
        "DATE(#{self.queried_class.table_name}.started_on) = '#{Time.now.localtime.to_date}'"
      when ">t+"
        "DATE(#{self.queried_class.table_name}.started_on) > '#{(Time.now.localtime+value[0].to_i.days).to_date}'"
      when "<t+"
        "DATE(#{self.queried_class.table_name}.started_on) < '#{(Time.now.localtime+value[0].to_i.days).to_date}' AND DATE(#{self.queried_class.table_name}.started_on) > '#{(Time.now.localtime.to_date)}'"
      when ">t-"
        "DATE(#{self.queried_class.table_name}.started_on) > '#{(Time.now.localtime-value[0].to_i.days).to_date}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{(Time.now.localtime.to_date)}'"
      when ">t-"
        "DATE(#{self.queried_class.table_name}.started_on) < '#{(Time.now.localtime-value[0].to_i.days).to_date}'"
      when "t+"
        "DATE(#{self.queried_class.table_name}.started_on) = '#{(Time.now.localtime+value[0].to_i.days).to_date}'"
      when "t-"
        "DATE(#{self.queried_class.table_name}.started_on) = '#{(Time.now.localtime-value[0].to_i.days).to_date}'"
      when "w"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{Time.now.localtime.beginning_of_week.to_date}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{Time.now.localtime.end_of_week.to_date}'"
      # following filter is used as workaround for custom-filters. so the logic implemented here is not "none"!
      # instead it represents "this month"
      when "*"
        "DATE(#{self.queried_class.table_name}.started_on) IS NOT NULL"
      when "!*"
        "DATE(#{self.queried_class.table_name}.started_on) IS NULL"
      when "ld"
        "DATE(#{self.queried_class.table_name}.started_on) = '#{Time.now.localtime.yesterday.to_date}'"
      when "lw"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{(Time.now.localtime-1.weeks).beginning_of_week.to_date}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{(Time.now.localtime-1.weeks).end_of_week.to_date}'"
      when "l2w"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{(Time.now.localtime-2.weeks).beginning_of_day.to_date}'"
      when "lm"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{(Time.now.localtime.months_since(-1).beginning_of_month.to_date)}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{(Time.now.localtime.months_since(-1).end_of_month.to_date)}'"
      when "m"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{(Time.now.localtime.beginning_of_month.to_date)}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{(Time.now.localtime.end_of_month.to_date)}'"
      when "y"
        "DATE(#{self.queried_class.table_name}.started_on) >= '#{Time.now.localtime.beginning_of_year.to_date}' AND DATE(#{self.queried_class.table_name}.started_on) <= '#{Time.now.localtime.end_of_year.to_date}'"
    end
  end
  
  def sql_for_tt_user_field(field, operator, value)
    if value.delete('me')
      value += User.current.id.to_s.to_a
    end
    "( #{User.table_name}.id #{operator == "=" ? 'IN' : 'NOT IN'} (" + value.collect { |val| "'#{connection.quote_string(val)}'" }.join(",") + ") )"
  end
  
  def initialize_available_filters
    principals = []

    if project
      principals += project.principals.sort
      unless project.leaf?
        subprojects = project.descendants.visible.all
        principals += Principal.member_of(subprojects)
      end
    else
      if all_projects.any?
        principals += Principal.member_of(all_projects)
      end
    end
    principals.uniq!
    principals.sort!
    users = principals.select { |p| p.is_a?(User) }

    auth_values()
    
    author_values = []
    author_values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?
    author_values += users.collect { |s| [s.name, s.id.to_s] }
    add_available_filter('tt_user', :type => :list, :values => author_values) unless author_values.empty?
  end
  
  def custom_field_value
    c = group_by_column
    if c.is_a?(QueryCustomFieldColumn)
      r = r.keys.inject({}) { |h, k| h[c.custom_field.cast_value(k)] = r[k]; h }
    end
  end
  
  

end