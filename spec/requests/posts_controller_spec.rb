# frozen_string_literal: true

require 'rails_helper'

describe PostsController do
  fab!(:user) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }
  fab!(:post_1) { Fabricate(:post, user: moderator) }

  before do
    SiteSetting.set(:discourse_staff_alias_username, 'some_alias')
    SiteSetting.set(:discourse_staff_alias_enabled, true)
  end

  describe '#create' do
    it 'returns the right response when an invalid user is trying to post as alias user' do
      sign_in(user)

      post "/posts.json", params: {
        raw: 'this is a post',
        topic_id: post_1.topic_id,
        reply_to_post_number: 1,
        as_staff_alias: true
      }

      expect(response.status).to eq(403)
    end

    it 'does not allow a whisper to be posted as an alias user' do
      sign_in(moderator)
      alias_user = DiscourseStaffAlias.alias_user

      expect do
        post "/posts.json", params: {
          raw: 'this is a post',
          topic_id: post_1.topic_id,
          reply_to_post_number: 1,
          as_staff_alias: true,
          whisper: "true"
        }

        expect(response.status).to eq(403)
      end.to_not change { alias_user.posts.count }
    end

    it 'allows a staff user to post as alias user' do
      sign_in(moderator)
      alias_user = DiscourseStaffAlias.alias_user

      expect do
        post "/posts.json", params: {
          raw: 'this is a post',
          topic_id: post_1.topic_id,
          reply_to_post_number: 1,
          as_staff_alias: true
        }
      end.to change { alias_user.posts.count }.by(1)

      post = alias_user.posts.last

      expect(post.raw).to eq('this is a post')
      expect(post.topic_id).to eq(post_1.topic_id)
      expect(post.custom_fields[DiscourseStaffAlias::REPLIED_AS_ALIAS]).to eq(true)

      expect(DiscourseStaffAlias::UsersPostLinks.exists?(
        user_id: moderator.id,
        post_id: post.id,
        action: DiscourseStaffAlias::UsersPostLinks::ACTIONS['create']
      )).to eq(true)
    end
  end

  describe '#update' do
    it 'does not allow staff user to edit normal posts as alias user' do
      sign_in(moderator)

      put "/posts/#{post_1.id}.json", params: {
        post: {
          raw: 'new raw body',
          edit_reason: 'typo'
        },
        as_staff_alias: true
      }

      expect(response.status).to eq(403)
    end

    it 'allows a staff user to edit alised posts as alias user' do
      sign_in(moderator)

      post "/posts.json", params: {
        raw: 'this is a post',
        topic_id: post_1.topic_id,
        reply_to_post_number: 1,
        as_staff_alias: true
      }

      post_2 = Post.last

      expect do
        put "/posts/#{post_2.id}.json", params: {
          post: {
            raw: 'new raw body',
            edit_reason: 'typo'
          },
          as_staff_alias: true
        }
      end.to change { post_2.revisions.count }.by(1)

      post_2.reload

      expect(post_2.raw).to eq('new raw body')

      revision = post_2.revisions.last

      expect(revision.user_id).to eq(DiscourseStaffAlias.alias_user.id)

      expect(DiscourseStaffAlias::UsersPostLinks.exists?(
        user_id: moderator.id,
        post_id: post_2.id,
        action: DiscourseStaffAlias::UsersPostLinks::ACTIONS[
          DiscourseStaffAlias::UsersPostLinks::UPDATE_POST_ACTION
        ]
      )).to eq(true)
    end
  end
end