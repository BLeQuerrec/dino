using Gee;
using Xmpp;

using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.OpenPgp {

    public class Manager : StreamInteractionModule, Object {
        public static ModuleIdentity<Manager> IDENTITY = new ModuleIdentity<Manager>("pgp_manager");
        public string id { get { return IDENTITY.id; } }

        public const string MESSAGE_ENCRYPTED = "pgp";

        private StreamInteractor stream_interactor;
        private Database db;
        private HashMap<Jid, string> pgp_key_ids = new HashMap<Jid, string>(Jid.hash_bare_func, Jid.equals_bare_func);

        public static void start(StreamInteractor stream_interactor, Database db) {
            Manager m = new Manager(stream_interactor, db);
            stream_interactor.add_module(m);
        }

        private Manager(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;

            stream_interactor.account_added.connect(on_account_added);
            stream_interactor.get_module(MessageProcessor.IDENTITY).pre_message_received.connect(on_pre_message_received);
            stream_interactor.get_module(MessageProcessor.IDENTITY).pre_message_send.connect(on_pre_message_send);
        }

        private void on_pre_message_received(Entities.Message message, Xmpp.Message.Stanza message_stanza, Conversation conversation) {
            if (MessageFlag.get_flag(message_stanza) != null && MessageFlag.get_flag(message_stanza).decrypted) {
                message.encryption = Encryption.PGP;
            }
        }

        private void on_pre_message_send(Entities.Message message, Xmpp.Message.Stanza message_stanza, Conversation conversation) {
            if (message.encryption == Encryption.PGP) {
                string? key_id = get_key_id(conversation.account, message.counterpart);
                bool encrypted = false;
                if (key_id != null) {
                    Core.XmppStream? stream = stream_interactor.get_stream(conversation.account);
                    if (stream != null) encrypted = stream.get_module(Module.IDENTITY).encrypt(message_stanza, key_id);
                }
                if (!encrypted) {
                    message.marked = Entities.Message.Marked.WONTSEND;
                }
            }
        }

        public string? get_key_id(Account account, Jid jid) {
            return db.get_contact_key(jid);
        }

        private void on_account_added(Account account) {
            stream_interactor.module_manager.get_module(account, Module.IDENTITY).received_jid_key_id.connect((stream, jid, key_id) => {
                on_jid_key_received(account, new Jid(jid), key_id);
            });
        }

        private void on_jid_key_received(Account account, Jid jid, string key_id) {
            lock (pgp_key_ids) {
                if (!pgp_key_ids.has_key(jid) || pgp_key_ids[jid] != key_id) {
                    if (!stream_interactor.get_module(MucManager.IDENTITY).is_groupchat_occupant(jid, account)) {
                        db.set_contact_key(jid.bare_jid, key_id);
                    }
                }
                pgp_key_ids[jid] = key_id;
            }
        }
    }
}