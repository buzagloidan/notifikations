import { ICredentialType, INodeProperties } from 'n8n-workflow';

export class NotifikationsApi implements ICredentialType {
	name = 'notifikationsApi';
	displayName = 'Notifikations';
	documentationUrl = 'https://notifikations.com/docs.html';
	properties: INodeProperties[] = [
		{
			displayName: 'Webhook Secret',
			name: 'secret',
			type: 'string',
			typeOptions: { password: true },
			default: '',
			placeholder: 'ntf_dev_…',
			description:
				'Your device or user webhook secret from the Notifikations app. Find it in the app under Webhook URL — copy only the last path segment.',
		},
	];
}
